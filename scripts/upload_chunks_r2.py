#!/usr/bin/env python3
"""Upload HL2 asset chunks to Cloudflare R2 via S3-compatible API."""
import os, sys, boto3
from botocore.config import Config

R2_ACCESS_KEY = os.environ.get('R2_ACCESS_KEY_ID', '')
R2_SECRET_KEY = os.environ.get('R2_SECRET_ACCESS_KEY', '')
R2_ENDPOINT = 'https://bdeeeb229289da950d71472c4c4bab76.r2.cloudflarestorage.com'
R2_BUCKET = 'hl2-webxr-assets'

if not R2_ACCESS_KEY or not R2_SECRET_KEY:
    print('ERROR: R2 credentials not set. Need R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY')
    sys.exit(1)

s3 = boto3.client('s3',
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY,
    aws_secret_access_key=R2_SECRET_KEY,
    config=Config(signature_version='s3v4'),
    region_name='auto'
)

chunks_dir = sys.argv[1] if len(sys.argv) > 1 else 'chunks'
if not os.path.isdir(chunks_dir):
    print(f'ERROR: {chunks_dir} directory not found')
    sys.exit(1)

for fname in sorted(os.listdir(chunks_dir)):
    if not fname.endswith('.data'):
        continue
    fpath = os.path.join(chunks_dir, fname)
    size_mb = os.path.getsize(fpath) / 1024 / 1024
    print(f'Uploading {fname} ({size_mb:.1f} MB)...', end=' ', flush=True)
    try:
        s3.upload_file(fpath, R2_BUCKET, f'chunks/{fname}',
            ExtraArgs={'ContentType': 'application/octet-stream',
                       'ACL': 'public-read'})
        print('OK')
    except Exception as e:
        print(f'FAILED: {e}')
        sys.exit(1)

print('All chunks uploaded to R2!')
