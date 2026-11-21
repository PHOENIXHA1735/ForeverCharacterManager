"""Lossless public-only Lua serialization. The schema and numeric serializer stay shared."""
import re,math
from fcm_history_records import lua
KEY=re.compile('[A-Za-z_][A-Za-z0-9_]*')
RESERVED=frozenset('and break do else elseif end false for function if in local nil not or repeat return then true until while'.split())
def compact(value):
    if isinstance(value,dict):
        fields=[]
        for key in sorted(value,key=str):
            v=value[key]
            if v is None:continue  # Named nil fields are absent in the original Lua model too.
            name=str(key)
            target=name if KEY.fullmatch(name) and name not in RESERVED else '['+lua(name)+']'
            fields.append(target+'='+compact(v))
        return '{'+','.join(fields)+'}'
    if isinstance(value,list):return '{'+','.join(compact(v) for v in value)+'}'
    if type(value) is float and not math.isfinite(value):raise ValueError('Nonfinite output')
    return lua(value)
def payload(summary):
    if (summary.get('classification')!='public30' or summary.get('providerID')!='FCMPublicHistory'
            or summary.get('baselineHorizon')!=30 or summary.get('windows')!=[7,30]):
        raise ValueError('Public30 export required')
    return ('FCM_PublicHistory='+compact(summary)+'\n').encode('utf-8')
