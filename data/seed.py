"""
Seeds the database with synthetic tickets via the API.
Run AFTER generate_dataset.py and AFTER the backend is running.
Usage: python seed.py --url http://localhost:8000 --count 50
       python seed.py --url https://YOUR_VM_IP:8443 --count 50 --no-verify
"""
import json
import httpx
import argparse
import time


def get_token(base_url: str, verify_ssl: bool) -> str:
    """Login as admin and return JWT token."""
    print("▶ Authenticating as admin...")
    r = httpx.post(
        f"{base_url}/api/auth/login",
        data={"username": "admin@ticket.local", "password": "Admin@2024!"},
        verify=verify_ssl,
        timeout=15,
    )
    r.raise_for_status()
    token = r.json()["access_token"]
    print("  ✓ Authenticated.")
    return token


def seed(base_url: str, count: int, verify_ssl: bool):
    with open("tickets.json") as f:
        tickets = json.load(f)[:count]

    token = get_token(base_url, verify_ssl)
    headers = {"Authorization": f"Bearer {token}"}

    print(f"▶ Seeding {len(tickets)} tickets to {base_url}...")
    success, failed = 0, 0
    for i, t in enumerate(tickets):
        try:
            r = httpx.post(
                f"{base_url}/api/tickets",
                json={
                    "title": t["title"],
                    "description": t["description"],
                    "submitter_email": t["submitter_email"],
                },
                headers=headers,
                timeout=30,
                verify=verify_ssl,
            )
            r.raise_for_status()
            success += 1
            print(f"  [{i+1}/{len(tickets)}] ✓ {t['title'][:55]}")
        except Exception as e:
            failed += 1
            print(f"  [{i+1}/{len(tickets)}] ✗ {e}")
        time.sleep(0.3)

    print(f"\n✅ Done. {success} created, {failed} failed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8000")
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--no-verify", action="store_true", help="Skip SSL verification (for self-signed certs)")
    args = parser.parse_args()
    seed(args.url, args.count, verify_ssl=not args.no_verify)
