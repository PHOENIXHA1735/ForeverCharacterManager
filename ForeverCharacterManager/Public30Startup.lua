local _, FCM = ...
local makeSHA = (function()
-- Incremental SHA-256 for stock Lua 5.1.
local mod=4294967296
local floor=math.floor
local X,A,R,S
local native=rawget(_G,"bit")
if type(native)=="table" and type(native.bxor)=="function" and type(native.band)=="function"
  and type(native.ror)=="function" and type(native.rshift)=="function" then
  X=function(a,b,c)
    if c then return native.bxor(a,b,c)%mod end
    return native.bxor(a,b)%mod
  end
  A=function(a,b) return native.band(a,b)%mod end
  R=function(a,b) return native.ror(a,b)%mod end
  S=function(a,b) return native.rshift(a,b) end
else
  local nibble={}
  for a=0,15 do
    local row={}
    nibble[a]=row
    for b=0,15 do
      local i,j,mask,value=a,b,1,0
      for _=1,4 do
        if i%2~=j%2 then value=value+mask end
        i,j,mask=floor(i/2),floor(j/2),mask*2
      end
      row[b]=value
    end
  end
  -- Pack all byte XOR results into a 64 KiB string. Only the fallback
  -- needs the table. Each 32-bit XOR then uses four byte lookups.
  local rows,row={},{}
  for a=0,255 do
    local high,low=nibble[floor(a/16)],nibble[a%16]
    for b=0,255 do row[b+1]=16*high[floor(b/16)]+low[b%16] end
    rows[a+1]=string.char(unpack(row))
  end
  local bytes=table.concat(rows)
  local byte=string.byte
  local function wordXor(a,b)
    local a1,b1=floor(a/256),floor(b/256)
    local a2,b2=floor(a/65536),floor(b/65536)
    local a3,b3=floor(a/16777216),floor(b/16777216)
    return byte(bytes,(a-a1*256)*256+b-b1*256+1)
      +256*byte(bytes,(a1-a2*256)*256+b1-b2*256+1)
      +65536*byte(bytes,(a2-a3*256)*256+b2-b3*256+1)
      +16777216*byte(bytes,a3*256+b3+1)
  end
  X=function(a,b,c)
    local result=wordXor(a,b)
    if c then return wordXor(result,c) end
    return result
  end
  -- Lua doubles represent the 33-bit sum exactly.
  A=function(a,b) return (a+b-wordXor(a,b))/2 end
  local powers={}
  for i=0,32 do powers[i]=2^i end
  R=function(n,b)
    local divisor=powers[b]
    local shifted=floor(n/divisor)
    return shifted+(n-shifted*divisor)*powers[32-b]
  end
  S=function(n,b) return floor(n/powers[b]) end
end
local K={
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function calculate(source, blocks)
  assert(type(source)=="string" and #source<=8*1024*1024,"Invalid bounded digest input")
  local n=#source*8
  local whole=floor(#source/64)*64
  local tail=source:sub(whole+1)..string.char(128)..string.rep("\0",(55-#source)%64)..
    string.char(0,0,0,0,floor(n/2^24)%256,floor(n/2^16)%256,floor(n/256)%256,n%256)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local w={}
  local work=0
  for off=1,whole+#tail,64 do
    local s,prefix=source,off
    if off>whole then s,prefix=tail,off-whole end
    for i=1,16 do
      local p=prefix+(i-1)*4
      local a,b,c,d=s:byte(p,p+3)
      w[i]=((a*256+b)*256+c)*256+d
    end
    for i=17,64 do
      local a,b=w[i-15],w[i-2]
      w[i]=(w[i-16]+X(R(a,7),R(a,18),S(a,3))+w[i-7]+X(R(b,17),R(b,19),S(b,10)))%mod
    end
    local a,b,c,d,e,f,g,z=unpack(h)
    for i=1,64 do
      local t=(z+X(R(e,6),R(e,11),R(e,25))+A(e,f)+A(mod-1-e,g)+K[i]+w[i])%mod
      local u=(X(R(a,2),R(a,13),R(a,22))+A(a,b)+A(c,X(a,b)))%mod
      z,g,f,e,d,c,b,a=g,f,e,(d+t)%mod,c,b,a,(t+u)%mod
    end
    h[1],h[2],h[3],h[4]=(h[1]+a)%mod,(h[2]+b)%mod,(h[3]+c)%mod,(h[4]+d)%mod
    h[5],h[6],h[7],h[8]=(h[5]+e)%mod,(h[6]+f)%mod,(h[7]+g)%mod,(h[8]+z)%mod
    work=work+1
    if work==blocks and off+64<=whole+#tail then
      work=0
      coroutine.yield()
    end
  end
  for i=1,8 do h[i]=string.format("%08x",h[i]) end
  return table.concat(h)
end


return function(source,blocks)
  assert(type(source)=="string" and #source<=8*1024*1024,"Invalid bounded digest input")
  assert(type(blocks)=="number" and blocks>=1 and blocks<=8 and blocks%1==0,"Invalid block budget")
  local task=coroutine.create(function() return calculate(source,blocks) end)
  local result
  return function()
    if result then return true,result end
    local ok,value=coroutine.resume(task)
    if not ok then error(value) end
    if coroutine.status(task)=="dead" then result=value;return true,result end
    return false,nil
  end
end

end)()
local makeDirectory = (function()
-- Disposable stock Lua 5.1 decoder and authenticated page reader.
-- No source evaluation. Only bounded, positionally defined byte fields.
local function reader(bytes,cap)
  assert(type(bytes)=="string" and #bytes<=cap,"size limit")
  local pos=1
  local function take(limit)
    local _,last,n=bytes:find("^(%d+):",pos)
    assert(n and #n<=5 and (#n==1 or n:sub(1,1)~="0"),"noncanonical length")
    n=tonumber(n)
    assert(n<=limit and last+n<=#bytes,"field size")
    pos=last+n+1
    return bytes:sub(last+1,last+n)
  end
  return take,function() assert(pos==#bytes+1,"trailing or duplicate fields") end
end
local function int(s)
  assert(#s<=16 and (s=="0" or s:match("^[1-9]%d*$")),"integer format")
  local n=tonumber(s)
  assert(n<=9007199254740991 and string.format("%.0f",n)==s,"integer range")
  return n
end
local function number(s)
  if s=="0" then return 0 end
  local sign,m,exp=s:match("^([+-])(%d+):(-?%d+)$")
  assert(sign and #m==16 and #exp<=5,"number format")
  m,exp=int(m),tonumber(exp)
  local n=math.ldexp(m,exp-53)
  assert(n>0 and n<math.huge,"number range")
  local a,b=math.frexp(n)
  assert(a*2^53==m and b==exp and s==sign..string.format("%.0f",m)..":"..exp,"noncanonical number")
  return sign=="-" and -n or n
end
local function hex(s,n)
  return #s==n and s:match("^[0-9a-f]+$")
end
local function market(s)
  local r,f,g=s:match("^forever/([a-z]+)/([a-z]+)/([a-z]+)$")
  local rules={normal=true,pvp=true,rp=true,rppvp=true}
  return rules[r] and (f=="alliance" or f=="horde") and (g=="us" or g=="eu" or g=="cn")
end
local function decodeRecord(bytes,item,cutoff,asof)
  local take,done=reader(bytes,4096)
  local id=int(take(16))
  assert(id==item and id>0,"record identity")
  local stamp=int(take(16))
  assert(stamp>=cutoff and stamp<=asof,"record timestamp")
  local r={id=id,currentUtc=stamp,currentSource="scan"}
  for _,key in ipairs({"current","minimum","maximum","comparisonPct"}) do r[key]=number(take(24)) end
  assert(r.minimum>0 and r.current>=r.minimum and r.current<=r.maximum,"price bounds")
  for _,key in ipairs({"low","supply","volatility","trendPct"}) do
    local v=take(24)
    if #v>0 then
      r[key]=number(v)
      assert(key=="trendPct" or r[key]>=0 and (key~="low" or r[key]>0),"optional bounds")
    end
  end
  r.observedDays=int(take(2));r.observations=int(take(16));r.confidence=take(8)
  assert(r.observedDays>=1 and r.observedDays<=30 and r.observations>=r.observedDays,"observation bounds")
  assert(r.confidence=="low" or r.confidence=="moderate" and r.observedDays>=14,"confidence")
  r.ageSeconds=asof-stamp
  r.windows={}
  for _,w in ipairs({7,30}) do
    local d=int(take(2));local avg=take(24);local cov=number(take(24))
    assert(d<=w and d<=r.observedDays and cov==d/w and (d==0)==(#avg==0),"window evidence")
    local mean=#avg>0 and number(avg) or nil
    assert(not mean or mean>0,"invalid average")
    r.windows[tostring(w)]={days=d,average=mean,coverage=cov}
  end
  assert(r.windows["30"].days==r.observedDays,"baseline days")
  r.timing={}
  for _,mode in ipairs({"weekday","hour"}) do
    local max=mode=="weekday" and 7 or 24
    local count=int(take(2))
    assert(count<=max,"timing count")
    local prior=-1;local total=0;local bins={}
    for _=1,count do
      local k=int(take(2));local factor=number(take(24))
      local obs=int(take(16));local days=int(take(2));local adequate=take(1)
      assert(k>prior and k<max and factor>0 and days>=1 and days<=r.observedDays and obs>=days,"timing evidence")
      assert(adequate==(obs>=10 and days>=(mode=="weekday" and 4 or 5) and "1" or "0"),"timing adequacy")
      prior,total=k,total+obs
      bins[tostring(k)]={relative=factor,observations=obs,days=days,adequate=adequate=="1"}
    end
    assert(total==r.observations,"timing observation count")
    r.timing[mode]=bins
  end
  done()
  return r
end
local function frame(s) return #s..":"..s end
return function(sha)
  local function digest(domain,content)
    local step=sha(domain.."\0"..frame(content),4)
    while true do
      local done,result=step()
      if done then return result end
      coroutine.yield()
    end
  end
  local function task(operation)
    local co=coroutine.create(operation)
    local result
    return function()
      if result then return true,result end
      local success,value=coroutine.resume(co)
      assert(success,value)
      if coroutine.status(co)=="dead" then result=value;return true,value end
      return false,nil
    end
  end
  local page
  local function manifest(bytes,confirm,expectedMarket,now,expectedCutoff,expectedExpiry)
    return task(function()
      assert(type(confirm)=="string" and hex(confirm,64),"missing confirmation")
      local take,done=reader(bytes,65535)
      assert(digest("FCM30-DIRECTORY-v1",bytes)==confirm,"unconfirmed directory")
      assert(take(1)=="1","schema")
      local tx,gen=take(32),take(32)
      local m=take(48)
      assert(hex(tx,32) and hex(gen,32) and market(m) and m==expectedMarket,"directory identity")
      local cutoff,asof,expiry=int(take(16)),int(take(16)),int(take(16))
      assert(cutoff==expectedCutoff and expiry==expectedExpiry and cutoff<=asof and asof<=now and now<expiry,"invalid or expired window")
      local total,count=int(take(6)),int(take(4))
      assert(total<=100000 and count<=1024 and (total==0)==(count==0),"directory bounds")
      local pages,sum,last={},0,0
      for i=1,count do
        local id,first,finish,n=int(take(4)),int(take(16)),int(take(16)),int(take(2))
        local hash=take(64)
        assert(i==id and first>last and first<=finish and n>=1 and n<=16
          and (n==1)==(first==finish) and hex(hash,64),"invalid page descriptor")
        pages[i]={first=first,last=finish,count=n,sha256=hash}
        last,sum=finish,sum+n
        if i%16==0 then coroutine.yield() end
      end
      assert(sum==total,"record count mismatch")
      done()
      local d={transaction=tx,generation=gen,market=m,cutoff=cutoff,asof=asof,expiry=expiry,total=total}
      local invalid=false
      local function current(at,token)
        if token~=confirm or at<asof or at>=expiry then invalid=true end
        assert(not invalid,"confirmation changed or expired")
      end
      return function(operation,value,at,token,provided)
        current(at,token)
        if operation=="count" then return total,#pages end
        if operation=="locate" then
          assert(type(value)=="number" and value>=1 and value<=9007199254740991 and value%1==0,"invalid request")
          for i,descriptor in ipairs(pages) do
            if value<descriptor.first then return false end
            if value<=descriptor.last then return i end
          end
          return false
        end
        assert(operation=="page" and pages[value],"unknown page")
        local work=page(provided,pages[value],value,d,at)
        local complete=false
        return function(stepAt,stepToken)
          current(stepAt,stepToken)
          assert(not complete,"verified rows cannot be reused as authority")
          local ready,rows=work()
          if ready then complete=true end
          return ready,rows
        end
      end
    end)
  end
  page=function(bytes,descriptor,index,d,now)
    return task(function()
      assert(now>=d.asof and now<d.expiry and descriptor,"unavailable page")
      local take,done=reader(bytes,65535)
      assert(digest("FCM30-PAGE-v1",bytes)==descriptor.sha256,"page commitment mismatch")
      assert(take(1)=="1" and take(32)==d.transaction and take(32)==d.generation
        and take(48)==d.market and int(take(4))==index and int(take(2))==descriptor.count,"page identity")
      local records,prior={},0
      for i=1,descriptor.count do
        local body=take(4096)
        local idReader=reader(body,4096)
        local id=int(idReader(16))
        assert(id>prior and id>=descriptor.first and id<=descriptor.last,"page order or boundary")
        records[i]=decodeRecord(body,id,d.cutoff,d.asof)
        prior=id
        if i%2==0 then coroutine.yield() end
      end
      done()
      assert(records[1].id==descriptor.first and prior==descriptor.last,"page endpoints")
      return records
    end)
  end
  return manifest,page
end

end)()(makeSHA)
local makeAdapter = (function()
-- Authenticated records and verification state stay inside this closure.
return function(f,newSHA,newDirectory,getCommit)
  local token,meta,access,work,records,pages,hashes,phase,count,items,verifiedPages
  local function clone(x)
    if type(x)~="table" then return x end
    local r={}
    for k,v in pairs(x) do r[k]=clone(v) end
    return r
  end
  local function clear()
    token,meta,access,work,records,pages,phase,items=nil,nil,nil,nil,nil,nil,nil,nil
  end
  local function current()
    if not token or getCommit()~=token or f:Now()<meta.asOf or f:Now()>=meta.validUntil then
      clear();return false
    end
    return true
  end
  local function metadata(bytes)
    local values={}
    local pos=1
    for i=1,17 do
      local _,last,n=bytes:find("^(%d+):",pos)
      assert(n and #n<=4 and (#n==1 or n:sub(1,1)~="0"),"malformed authenticated header")
      n=tonumber(n)
      assert(n<=160 and last+n<=#bytes,"header length")
      values[i]=bytes:sub(last+1,last+n);pos=last+n+1
    end
    assert(pos==#bytes+1 and values[1]=="1" and values[13]=="committed","unconfirmed header")
    local function integer(s)
      local x=tonumber(s)
      assert(x and x==math.floor(x) and x>=0 and x<=9007199254740991 and string.format("%.0f",x)==s,"metadata integer")
      return x
    end
    local m={schema=2,interfaceVersion=2,engineRevision=values[2],providerID="FCMPublicHistory",
      classification="public30",timezone="America/Los_Angeles",baselineHorizon=30,
      rootInstanceID=values[3],datasetID=values[4],generation=integer(values[5]),
      asOf=integer(values[6]),validUntil=integer(values[7]),dayBoundaryUtc=integer(values[7]),
      eligibleCutoffDate=values[8],eligibleCutoffUtc=integer(values[9]),publicationID=values[17],
      permissionSummary=values[10],recommendationsAllowed=values[16]=="1",variant="personal-only",
      authorizationPolicy=1,authorizations={},personalSales={},demandMaxAge=604800,
      provenanceSummary={providerObservations=0,eligibleSales=0,eligibleObservations=integer(values[15])},
      windows={7,30},markets={}}
    return m,values[11],values[12],integer(values[14])
  end
  local market,directory,dirJob,headerJob,header,metaToken,itemCount
  local function start(bytes,dir,wantedMarket)
    clear()
    if type(bytes)~="string" or #bytes>2048 or type(dir)~="string" or #dir>65535
       or type(getCommit())~="string" then return false end
    token=getCommit()
    local ok,m,digest,marketName,declaredItemCount=pcall(metadata,bytes)
    if not ok or wantedMarket~=marketName then clear();return false end
    meta,metaToken,market,directory,itemCount=m,digest,marketName,dir,declaredItemCount
    if not current() then return false end
    headerJob=newSHA("FCM30-HANDOFF-v1\0"..#bytes..":"..bytes,4)
    phase="header"
    records,pages,items,hashes,verifiedPages={},{},{},0,0
    return true
  end
  local function stepDirectory()
    if not current() then return false end
    if phase=="directory-done" then return true end
    local ok,ready,result
    if phase=="header" then
      ok,ready,result=pcall(headerJob)
      if not ok or ready and result~=token then clear();return false end
      if not ready then return false end
      local data=f.HistoryProvider:Validate(meta,"FCMPublicHistory","public30",{7,30},30)
      if not data then clear();return false end
      dirJob=newDirectory(directory,metaToken,market,f:Now(),meta.eligibleCutoffUtc,meta.validUntil)
      phase="directory";return false
    end
    ok,ready,result=pcall(dirJob)
    if not ok then clear();return false end
    if ready then
      access=result
      local n
      n,count=access("count",nil,f:Now(),metaToken)
      if n~=itemCount then clear();return false end
      phase="directory-done";return true
    end
    return false
  end
  local function stepPage(i,bytes)
    if not current() or phase~="directory-done" then return false end
    if pages[i] then return true end
    if type(bytes)~="string" or i<1 or i>count or i%1~=0 then clear();return false end
    if not work then
      local ok,value=pcall(access,"page",i,f:Now(),metaToken,bytes)
      if not ok then clear();return false end
      work={i=i,step=value};hashes=hashes+1
    end
    if work.i~=i then clear();return false end
    local ok,ready,result=pcall(work.step,f:Now(),metaToken)
    if not ok then clear();return false end
    if ready then
      local pageIds={}
      for _,r in ipairs(result) do
        records[r.id]=r
        items[tostring(r.id)]=r
        pageIds[#pageIds+1]=r.id
      end
      pages[i]=pageIds;verifiedPages=verifiedPages+1;work=nil;return true
    end
    return false
  end
  local function selected()
    if not current() or phase~="directory-done" then return nil,"Public30 verification pending or unavailable" end
    if verifiedPages~=count then return nil,"Public30 browse range incomplete" end
    return meta,items
  end
  local function lookup(id)
    if not current() or phase~="directory-done" then return nil,"unavailable" end
    local index=access("locate",id,f:Now(),metaToken)
    if index==false then return nil,"verified absent" end
    if not pages[index] then return nil,"unavailable" end
    if not records[id] then return nil,"verified absent" end
    return clone(records[id]),"verified"
  end
  local function range(first,last,minimum,order)
    if not current() or phase~="directory-done" or first<1 or last>count or first>last then return nil end
    local result={}
    for i=first,last do
      if not pages[i] then return nil end
      for _,id in ipairs(pages[i]) do
        if records[id].current>=minimum then result[#result+1]=clone(records[id]) end
      end
    end
    if order=="price-desc" then
      table.sort(result,function(a,b)
        if a.current==b.current then return a.id<b.id end
        return a.current>b.current
      end)
    elseif order~=nil then return nil end
    return result
  end
  return {start=start,stepDirectory=stepDirectory,stepPage=stepPage,selected=selected,lookup=lookup,
    range=range,count=function() return current() and phase=="directory-done" and count or nil end,
    hashCount=function() return hashes end, alive=current}
end

end)()
local queue, index = {}, 1
local publications = FCM_PublicHistoryConfirmations
local snapshot, finish
local function token(market)
  return type(publications)=="table" and FCM_PublicHistoryConfirmations==publications and publications[market] or nil
end
local function current()
  if #queue==0 then return false end
  for _,job in ipairs(queue) do
    if not job.reader.alive() then return false end
  end
  return true
end
local function step()
  local job=queue[index]
  if not job then return end
  if not job.page then
    if not job.reader.stepDirectory() then return end
    job.page=1
  elseif job.reader.stepPage(job.page,job.pages[job.page]) then
    job.page=job.page+1
    if job.page>job.reader.count() then index=index+1 end
  end
end
local function assemble()
  if not current() then return nil end
  local result
  for _,job in ipairs(queue) do
    local snapshot,items=job.reader.selected()
    if not snapshot then return nil end
    if not result then
      result=snapshot
    else
      if snapshot.rootInstanceID~=result.rootInstanceID or snapshot.datasetID~=result.datasetID or
         snapshot.generation~=result.generation or snapshot.publicationID~=result.publicationID or snapshot.asOf~=result.asOf or
         snapshot.validUntil~=result.validUntil or snapshot.eligibleCutoffUtc~=result.eligibleCutoffUtc then
        return nil
      end
      result.provenanceSummary.eligibleObservations=result.provenanceSummary.eligibleObservations+
          snapshot.provenanceSummary.eligibleObservations
    end
    result.markets[job.market]=items
  end
  -- The page decoder authenticated these records. Apply the provider's
  -- complete schema/evidence checks once, yielding between small batches.
  local checked=0
  return FCM.HistoryProvider:Validate(result,"FCMPublicHistory","public30",{7,30},30,function()
    checked=checked+1
    if checked==8 then checked=0;coroutine.yield() end
  end)
end
-- Internal consumers treat the stable snapshot as read-only.
FCM.ConfirmedPublicHistory = {selected=function()
  if snapshot and current() then return snapshot end
  if snapshot then snapshot=nil;queue={} end
  return nil,"Public30 verification pending or unavailable"
end}
if type(FCM_PublicHistoryPages)=="table" and type(FCM_PublicHistoryConfirmations)=="table" then
  for market,bundle in pairs(FCM_PublicHistoryPages) do
    if type(market)~="string" or type(bundle)~="table" or type(bundle[3])~="table" or
       not token(market) or #queue>=32 then queue={};break end
    local reader=makeAdapter(FCM,makeSHA,makeDirectory,function() return token(market) end)
    if not reader.start(bundle[1],bundle[2],market) then queue={};break end
    queue[#queue+1]={market=market,reader=reader,pages=bundle[3]}
  end
end
if #queue>0 then
  local frame=CreateFrame("Frame")
  local timer
  if type(debugprofilestop)=="function" then
    timer=debugprofilestop
  elseif type(GetTimePreciseSec)=="function" then
    timer=function() return GetTimePreciseSec()*1000 end
  end
  local function readClock()
    if not timer then return nil end
    local okay,stamp=pcall(timer)
    if okay and type(stamp)=="number" and stamp==stamp and stamp>=0 and stamp<math.huge then
      return stamp
    end
    timer=nil
  end
  local requested=tonumber(FCM.Public30VerificationBudgetMs)
  local budget=requested and requested==requested and math.max(2,math.min(4,requested)) or 4
  local estimatedStep=0
  frame:SetScript("OnUpdate",function(self)
    local start=readClock()
    local previous=start
    local limit=start and 16 or 2
    for _=1,limit do
      if not current() then
        queue={}
        self:SetScript("OnUpdate",nil)
        return
      end
      if index<=#queue then
        step()
      else
        finish=finish or coroutine.create(assemble)
        local okay,result=coroutine.resume(finish)
        if not okay or coroutine.status(finish)=="dead" then
          if okay and result and current() then snapshot=result end
          finish=nil
          self:SetScript("OnUpdate",nil)
          return
        end
      end
      if start then
        local stamp=readClock()
        if not stamp or stamp<previous then
          timer=nil
          return
        end
        -- A coroutine step cannot be preempted. Reserve time for the next
        -- step rather than starting another after spending the frame budget.
        estimatedStep=math.max(stamp-previous,estimatedStep*0.85)
        if stamp-start+estimatedStep>=budget then return end
        previous=stamp
      end
    end
  end)
end
