// SPDX-License-Identifier: LGPL-3.0-only
'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createProvider,ids,LyricsError}=require('../shared/providers.cjs');
const R=require('../shared/runtime.cjs');
const input={track:'Song',artist:'Artist',duration:180};
const lrc='[00:01.00]First\n[00:03.00]Second';
const lyric=()=>({lines:[{startTimeMs:1000,words:'First',endTimeMs:3000}],syncType:'LINE_SYNCED',instrumental:false,plainLyrics:''});
const error=(kind,message='fixture error')=>new LyricsError(kind,message);
function fixture(routes,overrides={}) {
  const calls=[],parses=[];
  const core={
    primaryArtist:x=>x.split(',')[0],simplifyTrack:x=>x.replace(/ \(Live\)$/,''),
    titlesMatch:(a,b)=>a===b,artistsMatch:(a,b)=>a===b,durationMatches:(a,b)=>!a || !b || Math.abs(a-b)<5,
    artistInTitle:(a,b)=>a.includes(b),score:()=>100,clockDuration:x=>typeof x==='number' ? x : String(x).split(':').reduce((a,b)=>a*60+Number(b),0),
    normalizeTitle:x=>String(x).toLowerCase(),normalizeLooseArtist:x=>String(x).toLowerCase().replace(/[,/]/g,' '),
    decode:(kind,raw)=>JSON.parse(raw),
    lrclibResponse:row=>row.instrumental ? {...lyric(),lines:[],instrumental:true} : lyric(),
    selectLrclib:rows=>rows[0] || null,
    fromText:(text,provider,source)=>{parses.push(['fromText',text,provider,source]);return {...lyric(),provider,source};},
    parseProxy:(raw,provider,deezer)=>{parses.push(['parseProxy',raw,provider,deezer]);return {...lyric(),provider};},
    ttmlLyrics:(...args)=>{parses.push(['ttmlLyrics',...args]);return {...lyric(),provider:args[1]};},
    formatKpoe:(...args)=>{parses.push(['formatKpoe',...args]);return lrc;},
    formatApple:(...args)=>{parses.push(['formatApple',...args]);return lrc;},
    formatZarzApple:(...args)=>{parses.push(['formatZarzApple',...args]);return lrc;},
    appleSupplements:(raw,value)=>({...value,lines:value.lines.map(l=>({...l,translation:'Translation',romanization:'Romanization'}))}),
    base64Text:(raw,noPadding)=>{parses.push(['base64Text',raw,noPadding]);return Buffer.from(raw,'base64').toString('utf8');},
    geniusText:raw=>{parses.push(['geniusText',raw]);return 'First\nSecond';},
    ...overrides.core,
  };
  const host={check:()=>{},core,request:async request=>{
    calls.push(request);const response=await routes(request,calls.length);
    if(response instanceof Error) throw response;
    return response && Object.hasOwn(response,'status') && Object.hasOwn(response,'body') ? response : {status:200,body:typeof response==='string' ? response : JSON.stringify(response)};
  },...overrides,core};
  return {host,calls,parses};
}
function routesFor(id) {
  return request=>{
    const url=new URL(request.url),p=url.pathname;
    if(id==='lrclib') return {track_name:'Song',artist_name:'Artist',synced_lyrics:lrc};
    if(id==='spotify') return p.endsWith('/search') ? [{track_id:'s',name:'Song',artist_name:'Artist',duration:'3:00'}] : '{"lyrics":"fixture"}';
    if(id==='deezer') return '{"lyrics":"fixture"}';
    if(id==='youtube') return p.endsWith('/search') ? [{video_id:'v',title:'Song',author:'Artist',duration:'3:00'}] : '{"lyrics":"fixture"}';
    if(id==='netease') return p.endsWith('/search') ? {code:200,result:{song_count:1,songs:[{id:1,name:'Song',artists:[{name:'Artist'}]}]}} : {lrc:{lyric:lrc},tlyric:{lyric:'[00:01.00]Translation'},romalrc:{lyric:'[00:01.00]Romanization'}};
    if(id==='musixmatch') return JSON.stringify(lrc);
    if(id==='lyricsplus') return {lyrics:[{text:'First'}]};
    if(id==='lrcred') return p.endsWith('search.json') ? {hits:[{isrc:'USABC1234567',title:'Song',artist:'Artist',duration:180}]} : '<tt>fixture</tt>';
    if(id==='betterlyrics') return {ttml:'<tt>fixture</tt>'};
    if(id==='apple_music' || id==='mornye_lyrics') {
      if(url.hostname==='beta.music.apple.com') return p==='/' ? '<script src="/assets/index~fixture.js"></script>' : 'eyJfixture.payload.signature';
      if(p.endsWith('/search')) return {results:{songs:{data:[{id:'1'}]}},resources:{songs:{'1':{attributes:{name:'Song',artist_name:'Artist',duration_in_millis:180000}}}}};
      return '{"lyrics":"fixture"}';
    }
    if(id==='qqmusic') {
      if(p.endsWith('smartbox_new.fcg')) return {code:0,data:{song:{itemlist:[{mid:'mid',id:'1',name:'Song',singer:'Artist'}]}}};
      if(p.endsWith('fcg_play_single_song.fcg')) return {code:0,data:[{interval:180}]};
      return {code:0,retcode:0,lyric:Buffer.from(lrc).toString('base64')};
    }
    if(id==='kugou') return p.endsWith('/search') ? {status:200,errcode:0,candidates:[{id:'1',accesskey:'key',song:'Song',singer:'Artist',duration:180000}]} : {status:200,error_code:0,content:Buffer.from(lrc).toString('base64')};
    if(id==='genius') return p.endsWith('/multi') ? {response:{sections:[{hits:[{kind:'song',result:{title:'Song',primary_artist_names:'Artist',url:'https://genius.com/fixture-lyrics'}}]}]}} : '<div data-lyrics-container="true">First<br>Second</div>';
    throw Error('Missing fixture route');
  };
}
for(const id of ids) {
  test(`${id}: staged source fetches through its own routes and returns native-parser output`,async()=>{
    const f=fixture(routesFor(id));
    const factory=require(`../sources/${id}/provider.cjs`),provider=factory(f.host);
    assert.equal(provider.id,id);assert.deepEqual(Object.keys(provider).sort(),['fetchLyrics','id']);
    const value=await provider.fetchLyrics({...input,spotify_id:id==='deezer' ? 'deezer:42' : ''});
    assert.equal(value.lines[0].words,'First');assert.ok(f.calls.length);
    assert.ok(f.calls.every(c=>c.url.startsWith('https://') && c.timeoutMs>0 && c.maxBytes>0));
    if(id==='lrclib') assert.equal(f.calls[0].headers['User-Agent'],R.browserUA);
    assert.equal(typeof provider.download,'undefined');
    if(id==='mornye_lyrics') {
      const request=f.calls.at(-1);assert.equal(request.timeoutMs,65000);assert.equal(new URL(request.url).searchParams.get('v'),'1');
      assert.equal(value.lines[0].translation,'Translation');assert.equal(value.lines[0].romanization,'Romanization');
    }
  });
  test(`${id}: cancellation before dispatch performs no network requests`,async()=>{
    const f=fixture(routesFor(id),{check(){throw Error('cancelled');}});
    await assert.rejects(createProvider(id,f.host).fetchLyrics(input),e=>e.kind==='cancelled');
    assert.equal(f.calls.length,0);
  });
}
test('all 14 Rust sources remain byte-identical to their recorded origin',()=>{
  const lock=require('../origin-lock.json');assert.deepEqual(lock.providers,ids);
  for(const entry of lock.rust_sources) {
    const content=fs.readFileSync(path.join(__dirname,'../../..',entry.path));
    assert.equal(crypto.createHash('sha256').update(content).digest('hex'),entry.sha256,entry.path);
  }
  assert.equal(fs.existsSync(path.join(__dirname,'../sources/jellyfin')),false);
});
test('transport outage stops variant retries',async()=>{
  const f=fixture(()=>error('unavailable'));
  await assert.rejects(createProvider('spotify',f.host).fetchLyrics({...input,artist:'Artist, Guest',track:'Song (Live)'}),e=>e.kind==='unavailable');
  assert.equal(f.calls.length,1);
});
test('last missing-result error is retained instead of throwing undefined',async()=>{
  const f=fixture(()=>error('not_found','no matching recording'));
  await assert.rejects(createProvider('spotify',f.host).fetchLyrics(input),e=>e.kind==='not_found' && e.message==='no matching recording');
  assert.equal(f.calls.length,1);
});
test('retry sequence preserves full artists, then simplifies eligible titles',async()=>{
  const f=fixture(()=>error('not_found'));
  await assert.rejects(createProvider('spotify',f.host).fetchLyrics({...input,artist:'Artist, Guest',track:'Song (Live)'}),e=>e.kind==='not_found');
  assert.deepEqual(f.calls.map(c=>new URL(c.url).searchParams.get('q')),['Song (Live) Artist','Song (Live) Artist, Guest','Song Artist']);
});
test('LyricsPlus tries its secondary server after an outage',async()=>{
  const happy=routesFor('lyricsplus');const f=fixture((r,n)=>n===1 ? error('unavailable') : happy(r));
  await createProvider('lyricsplus',f.host).fetchLyrics(input);
  assert.deepEqual(f.calls.map(c=>new URL(c.url).hostname),['lyricsplus.prjktla.my.id','lyricsplus.binimum.org']);
});
test('LyricsPlus cancellation never tries a secondary server',async()=>{
  const f=fixture(()=>error('cancelled'));
  await assert.rejects(createProvider('lyricsplus',f.host).fetchLyrics(input),e=>e.kind==='cancelled');assert.equal(f.calls.length,1);
});
test('NetEase preserves optional translation and romanization requests',async()=>{
  const f=fixture(routesFor('netease'));
  await createProvider('netease',f.host).fetchLyrics({...input,options:{include_translation_netease:true,include_romanization_netease:true}});
  assert.equal(f.parses.at(-1)[1],lrc+'\n\n[00:01.00]Translation\n\n[00:01.00]Romanization');
});
test('Musixmatch falls back from a failed translation to word lyrics',async()=>{
  const f=fixture((r,n)=>n===1 ? error('unavailable') : JSON.stringify(lrc));
  await createProvider('musixmatch',f.host).fetchLyrics({...input,options:{musixmatch_language:' AR '}});
  assert.deepEqual(f.calls.map(c=>new URL(c.url).searchParams.get('type')),['translate','word']);
  assert.equal(new URL(f.calls[0].url).searchParams.get('l'),'ar');
});
test('lrc.red retains collaborators and only safe ISRCs reach document paths',async()=>{
  const f=fixture(r=>r.url.includes('search.json') ? {hits:[
    {isrc:'../traversal',title:'Song',artist:'Artist Guest',duration:180},
    {isrc:'USABC1234567',title:'Song',artist:'Artist',duration:180},
    {isrc:'GBABC1234567',title:'Song',artist:'Guest / Artist',duration:181},
  ]} : '<tt/>');
  await createProvider('lrcred',f.host).fetchLyrics({...input,artist:'Artist, Guest'});
  assert.equal(new URL(f.calls.at(-1).url).pathname,'/s/GBABC1234567.ttml');
});
test('BetterLyrics key-required and cache-missing responses are misses',async()=>{
  const f=fixture(()=>({status:401,body:'API key required'}));
  await assert.rejects(createProvider('betterlyrics',f.host).fetchLyrics(input),e=>e.kind==='not_found');
});
test('Deezer resolver is used only with a valid Spotify identifier',async()=>{
  let resolved;const f=fixture(routesFor('deezer'),{resolveDeezerId:async id=>{resolved=id;return 'deezer:42';}});
  await createProvider('deezer',f.host).fetchLyrics({...input,spotify_id:'A'.repeat(22)});
  assert.equal(resolved,'A'.repeat(22));assert.equal(new URL(f.calls[0].url).searchParams.get('id'),'42');
});
test('Apple refreshes catalog token once on 401',async()=>{
  const happy=routesFor('apple_music');let searches=0;
  const f=fixture(r=>r.url.includes('/search?') && ++searches===1 ? {status:401,body:''} : happy(r));
  await createProvider('apple_music',f.host).fetchLyrics(input);
  assert.equal(searches,2);assert.equal(f.calls.filter(c=>new URL(c.url).hostname==='beta.music.apple.com').length,4);
});
test('Spotify/deezer IDs retain validation and signed i64 bounds',()=>{
  assert.equal(R.spotifyId('spotify:track:'+'A'.repeat(22)),'A'.repeat(22));
  assert.equal(R.spotifyId('deezer:42'),'');assert.equal(R.deezerId('9223372036854775808'),'');
  assert.equal(R.deezerId('deezer:42'),'42');assert.equal(R.i64(Infinity),'-9223372036854775808');assert.equal(R.i64(-0.5),'-1');
});
test('native word-timing settings reach TTML parser unchanged',async()=>{
  const f=fixture(routesFor('betterlyrics'));
  await createProvider('betterlyrics',f.host).fetchLyrics({...input,options:{multi_person_word_by_word:false,apple_elrc_word_sync:true}});
  assert.deepEqual(f.parses[0].slice(-2),[false,true]);
});
test('provider instance rejects overlapping calls and recovers after completion',async()=>{
  let release;const ready=new Promise(resolve=>{release=resolve;});const happy=routesFor('spotify');
  const f=fixture(async r=>{await ready;return happy(r);});const provider=createProvider('spotify',f.host);
  const first=provider.fetchLyrics(input);await assert.rejects(provider.fetchLyrics(input),e=>e.kind==='other' && /busy/.test(e.message));
  release();await first;await provider.fetchLyrics(input);
});
test('LRCLIB searches after metadata misses and preserves instrumental responses',async()=>{
  const f=fixture(r=>new URL(r.url).pathname==='/api/get' ? {status:404,body:''} : [{track_name:'Song',artist_name:'Artist',instrumental:true}]);
  const value=await createProvider('lrclib',f.host).fetchLyrics(input);
  assert.equal(value.instrumental,true);assert.equal(value.source,'LRCLIB Search');
  assert.deepEqual(f.calls.map(c=>new URL(c.url).pathname),['/api/get','/api/search']);
});
test('QQ checks the next candidate when the first recording has the wrong length',async()=>{
  const happy=routesFor('qqmusic');
  const f=fixture(r=>{
    const u=new URL(r.url);
    if(u.pathname.endsWith('smartbox_new.fcg')) return {code:0,data:{song:{itemlist:[
      {mid:'wrong',id:'1',name:'Song',singer:'Artist'},{mid:'correct',id:'2',name:'Song',singer:'Artist'},
    ]}}};
    if(u.pathname.endsWith('fcg_play_single_song.fcg')) return {code:0,data:[{interval:u.searchParams.get('songmid')==='wrong' ? 300 : 180}]};
    return happy(r);
  });
  await createProvider('qqmusic',f.host).fetchLyrics(input);
  assert.equal(new URL(f.calls.at(-1).url).searchParams.get('songmid'),'correct');
});
test('QQ keeps an unknown duration after a detail outage, matching the native fallback',async()=>{
  const happy=routesFor('qqmusic');const f=fixture(r=>r.url.includes('fcg_play_single_song') ? error('unavailable') : happy(r));
  await createProvider('qqmusic',f.host).fetchLyrics(input);
  assert.ok(f.calls.at(-1).url.includes('fcg_query_lyric_new'));
});
test('proxy payload errors keep missing and rate-limited results distinct',async()=>{
  for(const [body,kind] of [['{"message":"lyrics not found"}','not_found'],['{"error":"rate limit reached"}','unavailable']]) {
    const f=fixture(()=>body);
    await assert.rejects(createProvider('spotify',f.host).fetchLyrics({...input,spotify_id:'A'.repeat(22)}),e=>e.kind===kind);
  }
});
test('response body bounds reject oversized direct lyrics before parsing',async()=>{
  const f=fixture(()=>'x'.repeat(2*1024*1024+1));
  await assert.rejects(createProvider('qqmusic',f.host).fetchLyrics(input),e=>e.kind==='unavailable' && /limit/.test(e.message));
  assert.equal(f.parses.length,0);
});
test('HTTP 500 does not become confirmed missing lyrics',async()=>{
  const f=fixture(()=>({status:500,body:''}));
  await assert.rejects(createProvider('netease',f.host).fetchLyrics(input),e=>e.kind==='unavailable');
});
test('cancellation after a completed request prevents decoding and publication',async()=>{
  let cancelled=false;
  const f=fixture(()=>{cancelled=true;return routesFor('spotify')({url:'https://lyrics.paxsenix.org/spotify/search'});},
    {check(){if(cancelled) throw Error('cancelled');},core:{decode(){throw Error('Decoding after cancellation');}}});
  await assert.rejects(createProvider('spotify',f.host).fetchLyrics(input),e=>e.kind==='cancelled');
  assert.equal(f.calls.length,1);
});
