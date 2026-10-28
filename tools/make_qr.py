#!/usr/bin/env python3
"""QR code for the download page:  python3 tools/make_qr.py <https-url> <out.png>
Only real, public https URLs are accepted (a QR to localhost helps nobody)."""
import sys
from urllib.parse import urlparse

import qrcode
from qrcode.constants import ERROR_CORRECT_M


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    url, out = sys.argv[1], sys.argv[2]
    u = urlparse(url)
    if u.scheme != "https" or not u.hostname or u.hostname in ("localhost", "127.0.0.1"):
        sys.exit(f"Refusing to make a QR for a non-public URL: {url}")
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_M, box_size=12, border=2)
    qr.add_data(url)
    qr.make(fit=True)
    qr.make_image(fill_color="#0C110F", back_color="white").save(out)
    print(f"QR for {url} → {out}")


if __name__ == "__main__":
    main()
