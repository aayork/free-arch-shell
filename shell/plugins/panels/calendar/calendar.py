#!/usr/bin/env python3
"""Roseshell calendar backend.

Syncs events from iCloud (CalDAV, read/write) and plain ICS feed URLs
(Google/Microsoft "secret address in iCal format" links, read-only) into a
flat JSON cache the shell's Calendar plugin reads. Account metadata lives in
~/.local/state/roseshell/settings/calendar.json (no secrets); passwords are
stored via secret-tool (gnome-keyring), never written to disk in the clear.

Invoked by shell/plugins/panels/calendar/Service.qml as:
  python3 calendar.py <subcommand> [args...]
Every subcommand prints one JSON object to stdout and exits non-zero on
failure so the QML side can branch on Process.onExited without scraping text.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta

STATE_DIR = os.path.expanduser("~/.local/state/roseshell")
SETTINGS_PATH = os.path.join(STATE_DIR, "settings", "calendar.json")
EVENTS_PATH = os.path.join(STATE_DIR, "calendar", "events.json")
SECRET_SERVICE = "roseshell-calendar"
SYNC_DAYS_AHEAD = 14  # today .. +N days pulled on every sync

PALETTE = ["#4C9F70", "#4C7EA8", "#A85C9F", "#C98A3B", "#C1503E", "#6C7BC9"]


def _next_color(index):
    return PALETTE[index % len(PALETTE)]


def _atomic_write_json(path, data):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def load_settings():
    try:
        with open(SETTINGS_PATH) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    data.setdefault("accounts", [])
    return data


def save_settings(data):
    _atomic_write_json(SETTINGS_PATH, data)


def secret_store(account_id, password, label):
    subprocess.run(
        ["secret-tool", "store", "--label", label,
         "service", SECRET_SERVICE, "account", account_id],
        input=password, text=True, check=True,
    )


def secret_lookup(account_id):
    result = subprocess.run(
        ["secret-tool", "lookup", "service", SECRET_SERVICE, "account", account_id],
        capture_output=True, text=True,
    )
    return result.stdout if result.returncode == 0 else None


def secret_clear(account_id):
    subprocess.run(
        ["secret-tool", "clear", "service", SECRET_SERVICE, "account", account_id],
        capture_output=True, text=True,
    )


def account_id_for(provider, identifier):
    return "%s:%s" % (provider, identifier)


def fail(message):
    print(json.dumps({"ok": False, "error": str(message)}))
    sys.exit(1)


def cmd_add_icloud(args):
    import caldav

    email = args.email
    password = sys.stdin.readline().rstrip("\n")
    if not password:
        fail("no password provided on stdin")

    account_id = account_id_for("icloud", email)
    client = caldav.DAVClient(url="https://caldav.icloud.com", username=email, password=password)
    try:
        principal = client.principal()
        calendars = principal.calendars()
    except Exception as exc:
        fail("could not connect: %s" % exc)
        return

    cal_entries = []
    for cal in calendars:
        try:
            name = str(cal.name or "Calendar")
        except Exception:
            name = "Calendar"
        cal_entries.append({
            "url": str(cal.url),
            "displayName": name,
            "enabled": True,
            "color": _next_color(len(cal_entries)),
        })

    # Only store the credential once the connection (and thus the password)
    # is confirmed good.
    secret_store(account_id, password, "Roseshell Calendar: %s" % email)

    settings = load_settings()
    settings["accounts"] = [a for a in settings["accounts"] if a.get("id") != account_id]
    settings["accounts"].append({
        "id": account_id,
        "type": "caldav",
        "provider": "icloud",
        "label": email,
        "url": "https://caldav.icloud.com",
        "username": email,
        "enabled": True,
        "calendars": cal_entries,
    })
    save_settings(settings)
    print(json.dumps({"ok": True, "accountId": account_id, "calendars": len(cal_entries)}))


def cmd_add_ics(args):
    account_id = account_id_for("ics", args.label.lower().replace(" ", "-"))
    settings = load_settings()
    settings["accounts"] = [a for a in settings["accounts"] if a.get("id") != account_id]
    settings["accounts"].append({
        "id": account_id,
        "type": "ics",
        "provider": args.provider,
        "label": args.label,
        "url": args.url,
        "enabled": True,
        "calendars": [{
            "url": args.url,
            "displayName": args.label,
            "enabled": True,
            "color": _next_color(len(settings["accounts"])),
        }],
    })
    save_settings(settings)
    print(json.dumps({"ok": True, "accountId": account_id}))


def cmd_remove_account(args):
    settings = load_settings()
    settings["accounts"] = [a for a in settings["accounts"] if a.get("id") != args.account_id]
    save_settings(settings)
    secret_clear(args.account_id)
    print(json.dumps({"ok": True}))


def cmd_list_accounts(args):
    settings = load_settings()
    print(json.dumps({"ok": True, "accounts": settings["accounts"]}))


def _window():
    start = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=SYNC_DAYS_AHEAD)
    return start, end


def _normalize_vevent(component, account_id, calendar_name, color):
    dtstart = component.get("dtstart").dt
    dtend_prop = component.get("dtend")
    dtend = dtend_prop.dt if dtend_prop else dtstart
    all_day = not isinstance(dtstart, datetime)

    def iso(value):
        if isinstance(value, datetime):
            if value.tzinfo is None:
                value = value.astimezone()
            return value.isoformat()
        return datetime(value.year, value.month, value.day).isoformat()

    return {
        "uid": str(component.get("uid", uuid.uuid4())),
        "accountId": account_id,
        "calendar": calendar_name,
        "color": color,
        "title": str(component.get("summary", "(untitled)")),
        "location": str(component.get("location", "")),
        "start": iso(dtstart),
        "end": iso(dtend),
        "allDay": all_day,
    }


def _sync_caldav(account, start, end, errors):
    import caldav

    password = secret_lookup(account["id"])
    if not password:
        errors.append("%s: no stored password (re-add the account)" % account["label"])
        return []

    events = []
    try:
        client = caldav.DAVClient(url=account["url"], username=account["username"], password=password)
        principal = client.principal()
        configured = {c["url"]: c for c in account.get("calendars", [])}
        for cal in principal.calendars():
            meta = configured.get(str(cal.url))
            # Unconfigured calendars (added on iCloud after the account was
            # connected here) are skipped rather than silently shown.
            if configured and (not meta or not meta.get("enabled", True)):
                continue
            display_name = meta["displayName"] if meta else str(cal.name or "Calendar")
            color = meta["color"] if meta else "#888888"
            for result in cal.search(start=start, end=end, event=True, expand=True):
                for component in result.icalendar_instance.walk("VEVENT"):
                    events.append(_normalize_vevent(component, account["id"], display_name, color))
    except Exception as exc:
        errors.append("%s: %s" % (account["label"], exc))
    return events


def _sync_ics(account, start, end, errors):
    import icalendar
    import recurring_ical_events

    try:
        result = subprocess.run(
            ["curl", "-fsS", "--max-time", "10", account["url"]],
            capture_output=True, check=True,
        )
    except subprocess.CalledProcessError as exc:
        errors.append("%s: fetch failed (%s)" % (account["label"], exc))
        return []

    try:
        cal = icalendar.Calendar.from_ical(result.stdout)
    except Exception as exc:
        errors.append("%s: parse failed (%s)" % (account["label"], exc))
        return []

    color = (account.get("calendars") or [{}])[0].get("color", "#888888")
    events = []
    try:
        for component in recurring_ical_events.of(cal).between(start, end):
            events.append(_normalize_vevent(component, account["id"], account["label"], color))
    except Exception as exc:
        errors.append("%s: recurrence expansion failed (%s)" % (account["label"], exc))
    return events


def cmd_sync(args):
    settings = load_settings()
    start, end = _window()
    all_events = []
    errors = []
    for account in settings["accounts"]:
        if not account.get("enabled", True):
            continue
        if account.get("type") == "caldav":
            all_events.extend(_sync_caldav(account, start, end, errors))
        elif account.get("type") == "ics":
            all_events.extend(_sync_ics(account, start, end, errors))
    all_events.sort(key=lambda e: e["start"])
    _atomic_write_json(EVENTS_PATH, {
        "generatedAt": datetime.now().astimezone().isoformat(),
        "events": all_events,
        "errors": errors,
    })
    print(json.dumps({"ok": True, "count": len(all_events), "errors": errors}))


def cmd_create_event(args):
    import caldav
    from icalendar import Calendar as ICalendar, Event as IEvent

    payload = json.loads(sys.stdin.read())
    settings = load_settings()
    account = next((a for a in settings["accounts"] if a["id"] == payload["accountId"]), None)
    if not account:
        fail("unknown account")
        return

    password = secret_lookup(account["id"])
    if not password:
        fail("no stored password for this account")
        return

    client = caldav.DAVClient(url=account["url"], username=account["username"], password=password)
    principal = client.principal()
    target = next((c for c in principal.calendars() if str(c.url) == payload["calendarUrl"]), None)
    if not target:
        fail("unknown calendar")
        return

    ical = ICalendar()
    ical.add("prodid", "-//Roseshell Calendar//roseshell//")
    ical.add("version", "2.0")
    vevent = IEvent()
    vevent.add("summary", payload["title"])
    vevent.add("uid", str(uuid.uuid4()) + "@roseshell")
    start_dt = datetime.fromisoformat(payload["start"])
    end_dt = datetime.fromisoformat(payload["end"])
    if payload.get("allDay"):
        vevent.add("dtstart", start_dt.date())
        vevent.add("dtend", end_dt.date())
    else:
        vevent.add("dtstart", start_dt)
        vevent.add("dtend", end_dt)
    if payload.get("location"):
        vevent.add("location", payload["location"])
    ical.add_component(vevent)

    target.save_event(ical.to_ical())
    print(json.dumps({"ok": True}))


def cmd_delete_event(args):
    import caldav

    payload = json.loads(sys.stdin.read())
    settings = load_settings()
    account = next((a for a in settings["accounts"] if a["id"] == payload["accountId"]), None)
    if not account:
        fail("unknown account")
        return

    password = secret_lookup(account["id"])
    if not password:
        fail("no stored password for this account")
        return

    client = caldav.DAVClient(url=account["url"], username=account["username"], password=password)
    principal = client.principal()
    target = next((c for c in principal.calendars() if str(c.url) == payload["calendarUrl"]), None)
    if not target:
        fail("unknown calendar")
        return

    event = target.event_by_uid(payload["uid"])
    event.delete()
    print(json.dumps({"ok": True}))


def build_parser():
    parser = argparse.ArgumentParser(prog="calendar.py")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("add-icloud")
    p.add_argument("email")
    p.set_defaults(func=cmd_add_icloud)

    p = sub.add_parser("add-ics")
    p.add_argument("url")
    p.add_argument("--label", required=True)
    p.add_argument("--provider", default="ics")
    p.set_defaults(func=cmd_add_ics)

    p = sub.add_parser("remove-account")
    p.add_argument("account_id")
    p.set_defaults(func=cmd_remove_account)

    p = sub.add_parser("list-accounts")
    p.set_defaults(func=cmd_list_accounts)

    p = sub.add_parser("sync")
    p.set_defaults(func=cmd_sync)

    p = sub.add_parser("create-event")
    p.set_defaults(func=cmd_create_event)

    p = sub.add_parser("delete-event")
    p.set_defaults(func=cmd_delete_event)

    return parser


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except SystemExit:
        raise
    except Exception as exc:
        fail(exc)


if __name__ == "__main__":
    main()
