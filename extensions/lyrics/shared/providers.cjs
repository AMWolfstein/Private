// SPDX-License-Identifier: LGPL-3.0-only
'use strict';
const R=require('./runtime.cjs');
const {fail,usable,retryable,spotifyId,deezerId,browserUA}=R;
const pax='https://lyrics.paxsenix.org';
const artists=values=>(values || []).map(a=>String(a.name || '').trim()).filter(Boolean).join(', ');
const query=request=>`${request.track} ${request.artist}`;
function requiredQuery(request) { const q=query(request).trim(); if(!q) fail('not_found','empty search query'); return q; }

async function lrclib(c,r) {
  const primary=await c.call('primaryArtist',r.artist),simple=await c.call('simplifyTrack',r.track);
  const lookups=[[primary,r.track,'LRCLIB']];
  if(primary!==r.artist) lookups.push([r.artist,r.track,'LRCLIB']);
  if(simple!==r.track) lookups.push([primary,simple,'LRCLIB (simplified)']);
  async function accepted(action,source) {
    try { const value=await action();
      if(value && ((value.lines || []).length || value.instrumental)) return {...value,source};
    } catch(error) { if(!retryable(error)) throw error; }
    return null;
  }
  for(const [artist,track,source] of lookups) {
    const result=await accepted(async()=>{
      const row=await c.json(await c.get('https://lrclib.net/api/get',{artist_name:artist,track_name:track},{headers:{'User-Agent':browserUA}}),'lrclib',false);
      if(!await c.call('titlesMatch',row.track_name || row.name || '',track,false) || !await c.call('artistsMatch',row.artist_name,artist)) fail('not_found','LRCLIB returned mismatched track metadata');
      return c.call('lrclibResponse',row);
    },source);
    if(result) return result;
  }
  const searches=[[r.track,'LRCLIB Search']];
  if(simple!==r.track) searches.push([simple,'LRCLIB Search (simplified)']);
  for(const [track,source] of searches) {
    const result=await accepted(async()=>{
      const rows=await c.json(await c.get('https://lrclib.net/api/search',{q:`${primary} ${track}`},{headers:{'User-Agent':browserUA}}),'lrclib_list',false);
      const selected=await c.call('selectLrclib',rows || [],`${primary} ${track}`,track,primary,r.duration);
      if(!selected) fail('not_found','no matching lyrics found');
      return c.call('lrclibResponse',selected);
    },source);
    if(result) return result;
  }
  fail('not_found','LRCLIB: no lyrics found');
}
async function spotify(c,r) {
  let id=spotifyId(r.spotify_id);
  if(!id) {
    const songs=await c.call('decode','spotify_list',await c.proxy(`${pax}/spotify/search`,{q:requiredQuery(r)}),false);
    const song=await c.select(songs,r,async s=>{
      const duration=await c.call('clockDuration',s.duration);
      return {title:s.name,artist:s.artist_name,duration,allowed:await c.match(s.name,s.artist_name,duration,r)};
    });
    if(!song || !String(song.track_id || '').trim()) fail('not_found','no songs found on spotify');
    id=song.track_id.trim();
  }
  return c.call('parseProxy',await c.proxy(`${pax}/spotify/lyrics`,{id}),'Spotify',false);
}
async function deezer(c,r) {
  let id=deezerId(r.spotify_id);
  if(!id) {
    const spotify=spotifyId(r.spotify_id);
    if(!spotify) fail('not_found','deezer provider needs a deezer id or spotify id');
    c.check();
    if(typeof c.host.resolveDeezerId!=='function') fail('other','Deezer resolver unavailable');
    id=deezerId(await c.host.resolveDeezerId(spotify));c.check();
  }
  if(!id) fail('other','deezer id unavailable');
  return c.call('parseProxy',await c.proxy(`${pax}/deezer/lyrics`,{id}),'Deezer',true);
}
async function youtube(c,r) {
  const songs=await c.call('decode','youtube_list',await c.proxy(`${pax}/youtube/search`,{q:requiredQuery(r)}),false);
  const song=await c.select(songs,r,async s=>{
    const duration=await c.call('clockDuration',s.duration);
    const allowed=await c.call('titlesMatch',s.title,r.track,true) &&
      (await c.call('artistsMatch',s.author,r.artist) || await c.call('artistInTitle',s.title,r.artist)) &&
      await c.call('durationMatches',duration,r.duration);
    return {title:s.title,artist:s.author,duration,allowed};
  });
  if(!song || !String(song.video_id || '').trim()) fail('not_found','no songs found on youtube');
  return c.call('parseProxy',await c.proxy(`${pax}/youtube/lyrics`,{id:song.video_id.trim()}),'YouTube',false);
}
async function netease(c,r) {
  if(!query(r).trim()) fail('not_found','empty search query');
  const headers={Accept:'application/json','Accept-Language':'en-US,en;q=0.9','Cache-Control':'max-age=0'};
  const response=await c.json(await c.get(`${pax}/netease/search`,{q:query(r)},{headers}),'netease_search');
  if(response.code && response.code!==200) fail('unavailable',`netease search unavailable: ${response.code}`);
  if(!response.result?.song_count || !response.result?.songs?.length) fail('not_found','no songs found on netease');
  const song=await c.select(response.result.songs,r,async s=>{
    const artist=artists(s.artists);return {title:s.name,artist,duration:0,allowed:await c.match(s.name,artist,0,r)};
  });
  if(!song || !song.id) fail('not_found','no matching songs found on netease');
  const lyrics=await c.json(await c.get(`${pax}/netease/lyrics`,{id:String(song.id)},{headers}),'netease_lyrics');
  if(!lyrics.lrc?.lyric?.trim()) fail('not_found','no lyrics available on netease');
  let text=lyrics.lrc.lyric;
  for(const [include,line] of [[r.options.include_translation_netease,lyrics.tlyric],[r.options.include_romanization_netease,lyrics.romalrc]]) {
    if(include && line?.lyric?.trim()) text+='\n\n'+line.lyric;
  }
  try { return await c.text(text,'Netease'); } catch(error) { if(error.kind==='not_found') fail('other','netease returned empty lyrics'); throw error; }
}
async function musixmatch(c,r) {
  if(!r.track.trim() || !r.artist.trim()) fail('not_found','empty track or artist name');
  async function payload(type,language) {
    const params={t:r.track,a:r.artist,type,format:'lrc'};
    if(r.duration>0) params.d=R.i64(r.duration);
    if(language.trim()) params.l=language.trim().toLowerCase();
    const response=await c.get(`${pax}/musixmatch/lyrics`,params,{allowed:[]});
    const raw=response.body.trim();
    if(response.status!==200) fail(R.classify(response.status,R.payloadError(raw)),`musixmatch proxy returned HTTP ${response.status}`);
    let decoded;try { decoded=JSON.parse(raw); } catch {}
    if(decoded===null || typeof decoded==='string') {
      if(!String(decoded || '').trim()) fail('other','empty musixmatch lyrics payload');
      return decoded.trim();
    }
    const error=R.payloadError(raw);if(error) fail(R.classify(0,error),error);
    if(raw && !raw.startsWith('{')) return raw;
    fail('other','failed to decode musixmatch response');
  }
  const language=r.options.musixmatch_language.trim().toLowerCase();
  if(language) {
    try { return await c.text(await payload('translate',language),'Musixmatch',`Musixmatch (${language})`); }
    catch(error) { if(error.kind==='cancelled') throw error; }
  }
  return c.text(await payload('word',''),'Musixmatch');
}
async function lyricsplus(c,r) {
  if(!r.track.trim() || !r.artist.trim()) fail('other','lyricsplus: missing track or artist');
  let last=new R.LyricsError('not_found','lyricsplus: no lyrics found');
  for(const endpoint of ['https://lyricsplus.prjktla.my.id/v2/lyrics/get','https://lyricsplus.binimum.org/v2/lyrics/get']) {
    try {
      const params={title:r.track,artist:r.artist};
      if(r.duration>0) params.duration=r.duration.toFixed(3);
      const response=await c.get(endpoint,params,{allowed:[200,404]});
      if(response.status===404) fail('not_found','lyrics not found');
      const payload=await c.json(response,'kpoe');
      if(!payload.lyrics?.length) fail('other','lyricsplus returned no lines');
      const text=await c.call('formatKpoe',payload,r.options.multi_person_word_by_word,r.options.apple_elrc_word_sync);
      if(!text.trim()) fail('other','lyricsplus produced empty lyrics');
      const result=await c.call('fromText',text,'LyricsPlus','LyricsPlus');
      if(usable(result)) return result;
    } catch(error) { if(error.kind==='cancelled') throw error;last=error; }
  }
  throw last;
}
async function lrcred(c,r) {
  const search=await c.json(await c.get('https://lrc.red/search.json',{q:requiredQuery(r)},{unavailableErrors:true}),'lrc_red_search');
  const normalized=await c.call('normalizeTitle',r.track);
  async function artistWords(value) {return String(await c.call('normalizeLooseArtist',value)).split(/\s+/).filter(w=>w && !['feat','ft','featuring','with','and'].includes(w)).sort().join('\n');}
  const expected=await artistWords(r.artist);
  let best=null,distance=Infinity;
  for(const hit of search.hits || []) {
    const isrc=String(hit.isrc || '').trim().toUpperCase();
    if(!normalized || !expected || !/^[A-Z0-9]{12}$/.test(isrc) || await c.call('normalizeTitle',hit.title)!==normalized || await artistWords(hit.artist)!==expected || !await c.call('durationMatches',hit.duration,r.duration)) continue;
    const delta=hit.duration>0 && r.duration>0 ? Math.abs(hit.duration-r.duration) : Infinity;
    if(best===null || delta<distance) {best={...hit,isrc};distance=delta;}
  }
  if(!best) fail('not_found','no matching song found on lrc.red');
  const response=await c.get(`https://lrc.red/s/${best.isrc}.ttml`,{},{headers:{Accept:'application/ttml+xml, application/xml'},allowed:[200,404],unavailableErrors:true});
  if(response.status===404) fail('not_found','lrc.red has no lyrics for this song');
  return ttml(c,response.body,'lrc.red',r);
}
async function ttml(c,raw,source,r) {
  const result=await c.call('ttmlLyrics',raw,source,source,r.options.multi_person_word_by_word,r.options.apple_elrc_word_sync);
  if(!usable(result)) fail('not_found',`no lyrics found on ${source}`);return result;
}
async function betterlyrics(c,r) {
  if(!r.track.trim() || !r.artist.trim()) fail('not_found','empty search query');
  const params={s:r.track.trim(),a:r.artist.trim()};
  if(Number.isFinite(r.duration) && Math.round(r.duration)>0) params.d=R.i64(r.duration);
  const response=await c.get('https://lyrics-api.boidu.dev/getLyrics',params,{allowed:[200,401,404],unavailableErrors:true});
  if(response.status!==200) fail('not_found','betterlyrics has no cached lyrics');
  const payload=await c.json(response,'better_lyrics');
  if(!payload.ttml?.trim()) fail('not_found','betterlyrics returned no lyrics');
  return ttml(c,payload.ttml,'BetterLyrics',r);
}
async function apple(c,r,zarz) {
  const q=requiredQuery(r);
  async function token() {
    if(c.appleToken) return c.appleToken;
    const headers={'User-Agent':browserUA};
    const page=await c.get('https://beta.music.apple.com',{},{headers,timeoutMs:20000});
    const index=page.body.match(/\/assets\/index~[^"' <]+\.js/);
    if(!index) fail('other','apple music index script not found');
    const script=await c.get('https://beta.music.apple.com'+index[0],{},{headers,timeoutMs:20000});
    const jwt=script.body.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/);
    if(!jwt) fail('other','apple music token not found');
    c.check();c.appleToken=jwt[0];return jwt[0];
  }
  async function search() {
    const bearer=await token();
    const response=await c.get('https://amp-api.music.apple.com/v1/catalog/us/search',{
      term:q,types:'songs',limit:'25',l:'en-US',platform:'web','format[resources]':'map','include[songs]':'artists',extend:'artistUrl',
    },{timeoutMs:20000,allowed:[200,401],headers:{Authorization:`Bearer ${bearer}`,Origin:'https://music.apple.com',
      Referer:'https://music.apple.com/','User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:95.0) Gecko/20100101 Firefox/95.0',
      Accept:'application/json','Accept-Language':'en-US,en;q=0.5','x-apple-renewal':'true'}});
    return response.status===401 ? null : c.json(response,'apple_search');
  }
  let result=await search();
  if(result===null) {c.appleToken='';result=await search();}
  if(result===null) fail('other','apple music catalog search unauthorized');
  const songs=(result.results?.songs?.data || []).map(row=>({id:row.id,song:result.resources?.songs?.[row.id]?.attributes})).filter(row=>row.song);
  const selected=await c.select(songs,r,async row=>{
    const s=row.song,duration=(s.duration_in_millis || 0)/1000;
    return {title:s.name,artist:s.artist_name,duration,allowed:await c.match(s.name,s.artist_name,duration,r)};
  });
  if(!selected || !String(selected.id || '').trim()) fail('not_found','no songs found on apple music');
  const params={id:String(selected.id).trim()};if(zarz) params.v='1';
  const response=await c.get(zarz ? 'https://api.zarz.moe/apple-music/lyrics' : `${pax}/apple-music/lyrics`,params,
    {timeoutMs:zarz ? 65000 : 20000,allowed:[200,404]});
  if(response.status===404) fail('not_found','apple music lyrics not found');
  const raw=response.body.trim();
  if(!raw || raw.startsWith('<')) fail('unavailable','invalid lyrics response from apple music');
  const error=R.payloadError(raw);if(error) fail(R.classify(0,error),error);
  const name=zarz ? 'Zarz-LRC' : 'Apple Music';
  let text;
  try { text=await c.call(zarz ? 'formatZarzApple' : 'formatApple',raw,r.options.multi_person_word_by_word,r.options.apple_elrc_word_sync); }
  catch(error) { if(zarz || /^[{\[]/.test(raw) || error.kind==='cancelled') throw error;text=raw; }
  const lyrics=await c.text(text,name);
  // Preserve native supplementary translation/romanization fields.
  return c.call('appleSupplements',raw,lyrics);
}
async function direct(c,endpoint,params,qq=false) {
  const headers={Accept:'application/json'};
  if(qq) {headers.Referer='https://y.qq.com/';headers['User-Agent']=browserUA;}
  const response=await c.get(endpoint,params,{headers,maxBytes:2*1024*1024,unavailableErrors:true});
  if(!response.body.trim()) fail('unavailable','empty response');return response;
}
async function qqmusic(c,r) {
  const search=await c.json(await direct(c,'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg',{format:'json',key:requiredQuery(r)},true),'qq_search',false);
  if(search.code) fail('unavailable',`QQ Music search returned code ${search.code}`);
  const songs=[];
  for(const song of search.data?.song?.itemlist || []) {
    const artist=String(song.singer || '').replaceAll('/',', ');
    if(!String(song.mid || '').trim() || !await c.match(song.name,artist,0,r)) continue;
    songs.push({song,score:await c.call('score',song.name,artist,0,r.track,r.artist,r.duration)});
  }
  songs.sort((a,b)=>b.score-a.score);
  let selected;
  for(const {song} of songs.slice(0,3)) {
    try {
      const details=await c.json(await direct(c,'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg',{format:'json',songmid:song.mid},true),'qq_detail',false);
      const duration=details.code===0 ? details.data?.[0]?.interval : 0;
      if(duration>0 && !await c.call('durationMatches',duration,r.duration)) continue;
    } catch(error) {if(error.kind==='cancelled') throw error;}
    selected=song;break;
  }
  if(!selected) fail('not_found','no matching song found on QQ Music');
  const lyrics=await c.json(await direct(c,'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',{
    format:'json',inCharset:'utf8',outCharset:'utf-8',notice:'0',platform:'yqq.json',needNewCode:'0',songmid:selected.mid,songid:selected.id,
  },true),'qq_lyrics',false);
  if(lyrics.code || lyrics.retcode) fail('unavailable',`QQ Music lyrics returned code ${lyrics.code}`);
  const raw=String(lyrics.lyric || '').trim();if(!raw) fail('not_found','QQ Music returned empty lyrics');
  let text=raw;
  if(!raw.startsWith('[')) {
    try {text=await c.call('base64Text',raw,false);} catch(error) {
      if(error.kind==='cancelled') throw error;text=await c.call('base64Text',raw,true);
    }
  }
  return c.text(text,'QQ Music','QQ Music Direct');
}
async function kugou(c,r) {
  const search=await c.json(await direct(c,'https://lyrics.kugou.com/search',{
    ver:'1',man:'yes',client:'pc',keyword:`${r.artist} - ${r.track}`.trim(),duration:R.i64(r.duration*1000),hash:'',
  }),'kugou_search',false);
  if(search.status!==200 || search.errcode && search.errcode!==200) fail('unavailable',search.errmsg?.trim() || `status ${search.status}/error ${search.errcode}`);
  const song=await c.select(search.candidates,r,async s=>({title:s.song,artist:s.singer,duration:s.duration/1000,
    allowed:await c.match(s.song,s.singer,s.duration/1000,r)}));
  if(!song || !String(song.id || '').trim() || !String(song.accesskey || '').trim()) fail('not_found','no matching song found on kugou');
  const lyrics=await c.json(await direct(c,'https://lyrics.kugou.com/download',{
    ver:'1',client:'pc',id:song.id,accesskey:song.accesskey,fmt:'lrc',charset:'utf8',
  }),'kugou_lyrics',false);
  if(lyrics.status!==200 || lyrics.error_code) fail('unavailable',lyrics.info?.trim() || `status ${lyrics.status}/error ${lyrics.error_code}`);
  return c.text(await c.call('base64Text',lyrics.content,false),'Kugou','Kugou Direct');
}
async function genius(c,r) {
  const search=await c.call('decode','genius_search',await c.proxy('https://genius.com/api/search/multi',{q:requiredQuery(r),per_page:'5'}),false);
  const hits=(search.response?.sections || []).flatMap(s=>s.hits || []);
  const song=await c.select(hits,r,async hit=>{
    const s=hit.result || {},artist=s.primary_artist_names?.trim() ? s.primary_artist_names : s.artist_names;
    return {title:s.title,artist,duration:0,allowed:hit.kind==='song' && !!s.url?.trim() && await c.match(s.title,artist,0,r)};
  });
  if(!song) fail('not_found','no songs found on genius');
  const response=await c.get(song.result.url.trim(),{},{maxBytes:8*1024*1024,unavailableErrors:true,
    headers:{Accept:'text/html,application/xhtml+xml','Accept-Language':'en-US,en;q=0.9','User-Agent':browserUA}});
  return c.text(await c.call('geniusText',response.body),'Genius','Genius Direct');
}
const handlers={lrclib,spotify,deezer,youtube,netease,musixmatch,lyricsplus,lrcred,betterlyrics,qqmusic,kugou,genius,
  apple_music:(c,r)=>apple(c,r,false),mornye_lyrics:(c,r)=>apple(c,r,true)};
function createProvider(id,host) {
  if(!R.ids.includes(id)) throw new TypeError('Unknown lyrics provider');
  const context=R.createContext(host);
  // One request owns a context at a time. The future loader must serialize calls
  // to each provider VM; cancellation remains host-owned. Shared token coalescing
  // across separate provider instances is not implemented by this staged port.
  let busy=false;
  async function fetchLyrics(input={}) {
    if(busy) fail('other','lyrics provider busy');
    busy=true;
    try {
      const request={spotify_id:String(input.spotify_id || ''),track:String(input.track || ''),artist:String(input.artist || ''),
        album:String(input.album || ''),duration:Number(input.duration || 0),options:{...R.defaults,...input.options}};
      request.options.musixmatch_language=String(request.options.musixmatch_language || '').trim().toLowerCase();
      context.check();
      if(id==='lrclib' || id==='lrcred') return await handlers[id](context,request);
      const primary=await context.call('primaryArtist',request.artist),simple=await context.call('simplifyTrack',request.track);
      const attempt={...request,artist:primary};
      let lastError;
      try {return await handlers[id](context,attempt);} catch(error) {if(!retryable(error)) throw error;lastError=error;}
      if(primary!==request.artist) {
        try {return await handlers[id](context,request);} catch(error) {if(!retryable(error)) throw error;lastError=error;}
      }
      if(simple!==request.track && ['netease','spotify','youtube','kugou','genius','lyricsplus'].includes(id)) {
        return await handlers[id](context,{...attempt,track:simple,spotify_id:id==='spotify' ? '' : request.spotify_id});
      }
      // No successful attempt: preserve the final error without another request.
      throw lastError;
    } finally {busy=false;}
  }
  return Object.freeze({id,fetchLyrics});
}
module.exports={createProvider,ids:R.ids,LyricsError:R.LyricsError};
