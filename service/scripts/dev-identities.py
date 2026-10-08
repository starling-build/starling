#!/usr/bin/env python3
"""Generate local-only identity credentials. Never checked into the repository."""
import json
import os
from pathlib import Path
import secrets
path=Path(__file__).resolve().parents[1]/'.dev-identities.json'
identities={secrets.token_hex(32):{'issuer':'starling-local','subject':name,'name':name.title(),'email':name+'@example.test'}
            for name in ['alice','bob']}
with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:json.dump(identities,f,indent=2)
print('Created',path)
print('Use a token from this file as an Authorization: Bearer credential. Loopback service only.')
