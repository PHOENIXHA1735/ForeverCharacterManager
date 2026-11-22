"""Provider permissions require an independently reviewed, pinned document digest.
No CLI opt-in can populate the production trust set. Empty until legal/source review.
"""
import json,hashlib
APPROVED_PERMISSION_DIGESTS=frozenset()
class Permissions:
    def __init__(self,documents=(),*,trusted_digests=None):
        # Injection is for isolated tests / separately reviewed private distribution.
        self.trusted=APPROVED_PERMISSION_DIGESTS if trusted_digests is None else frozenset(trusted_digests)
        self.documents={d.get('id'):d for d in documents}
    @staticmethod
    def digest(d):return hashlib.sha256(json.dumps(d,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    def authorization(self,source,permission,now):
        d=self.documents.get(permission)
        if not d or self.digest(d) not in self.trusted or d.get('revoked') is True:return None
        if not d.get('reviewedBy') or source not in d.get('sources',[]) or not {'archive','statistics','export'}.issubset(d.get('uses',[])):return None
        expiry=d.get('expiresUtc');days=d.get('retentionDays')
        if type(expiry) is not int or expiry<=now or type(days) is not int or not 0<days<=365:return None
        return dict(digest=self.digest(d),expiresUtc=expiry,retentionDays=days)
    def days(self,source,permission,now):
        grant=self.authorization(source,permission,now)
        return grant['retentionDays'] if grant else 0
