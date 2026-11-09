// SPDX-License-Identifier: LGPL-3.0-only
'use strict';

const ids = Object.freeze(['lrclib','netease','musixmatch','apple_music','mornye_lyrics',
  'qqmusic','spotify','deezer','youtube','kugou','genius','lyricsplus','lrcred','betterlyrics']);
const defaults = Object.freeze({include_translation_netease:false,include_romanization_netease:false,
  multi_person_word_by_word:true,apple_elrc_word_sync:false,musixmatch_language:''});
const browserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
class LyricsError extends Error {
  constructor(kind, message) { super(message); this.name='LyricsError'; this.kind=kind; }
}
function fail(kind,message) { throw new LyricsError(kind,message); }
const statusKind = status => status===429 || status>=500 ? 'unavailable' : 'other';
const missed = text => ['lyrics not found','no lyrics found','no songs found','not found'].some(s=>String(text).toLowerCase().includes(s));
function classify(status,message) {
  if (missed(message)) return 'not_found';
  if (['rate limit','too many requests','operation too frequent','操作频繁','missing required parameters']
    .some(s=>String(message).toLowerCase().includes(s))) return 'unavailable';
  return statusKind(status);
}
function payloadError(raw) {
  const text=String(raw).trim();
  if (!text.startsWith('{')) return '';
  let value; try { value=JSON.parse(text); } catch { return ''; }
  if (['lyrics','lyric','lrc','content','lines','syncedLyrics','unsyncedLyrics'].some(k=>Object.hasOwn(value,k))) return '';
  for (const key of ['message','error','detail','reason']) if(typeof value[key]==='string' && value[key].trim()) return value[key].trim();
  if(value.success===false || value.isError===true) return 'request unsuccessful';
  if(typeof value.code==='number' && value.code!==0 && value.code!==200) return String(value.msg || `unexpected response code ${Math.round(value.code)}`);
  return '';
}
const usable = response => !!response && (response.instrumental===true ||
  (response.lines || []).some(line=>String(line.words || '').trim()) || String(response.plainLyrics || '').trim());
const retryable = error => !['unavailable','cancelled'].includes(error.kind);
function spotifyId(value) {
  let id=String(value || '').trim();
  if(/^deezer:/i.test(id)) return '';
  if(/^spotify:/i.test(id)) id=id.split(':').at(-1);
  if(id.includes('spotify.com/track/')) id=id.split('/track/')[1];
  id=id.split('?')[0].trim();
  return /^[A-Za-z0-9]{22}$/.test(id) ? id : '';
}
function deezerId(value) {
  let id=String(value || '').trim().replace(/^deezer:/i,'').trim();
  if(id.includes('deezer.com/')) id=id.split('/').at(-1);
  id=id.split('?')[0].trim();
  if(!/^[+-]?\d+$/.test(id)) return '';
  const number=BigInt(id);
  return number>=-(1n<<63n) && number<(1n<<63n) ? id : '';
}
function i64(value) {
  const rounded=value<0 ? -Math.round(-value) : Math.round(value);
  return !Number.isFinite(rounded) || rounded>=2**63 || rounded<-(2**63) ? '-9223372036854775808' : BigInt(rounded).toString();
}
function createContext(host) {
  if(!host || typeof host.request!=='function' || typeof host.check!=='function' || !host.core) {
    throw new TypeError('A lyrics host with request, check and native core helpers is required');
  }
  const core=host.core;
  function check() { try { host.check(); } catch { fail('cancelled','lyrics request cancelled'); } }
  async function call(name,...args) {
    check();
    if(typeof core[name]!=='function') fail('other',`native lyrics helper unavailable: ${name}`);
    const value=await core[name](...args); check(); return value;
  }
  async function get(endpoint,params={},options={}) {
    check();
    const url=new URL(endpoint);
    if(url.protocol!=='https:' || url.username || url.password) fail('other','lyrics requires HTTPS without URL credentials');
    for(const key of Object.keys(params).sort()) url.searchParams.append(key,String(params[key]));
    const allowed=options.allowed ?? [200];
    const request={url:url.href,headers:options.headers ?? {Accept:'application/json'},
      timeoutMs:options.timeoutMs ?? 15000,maxBytes:options.maxBytes ?? 16*1024*1024,
      allowedStatuses:allowed,unavailableErrors:!!options.unavailableErrors};
    let result;
    try { result=await host.request(request); } catch(error) {
      check(); if(error.kind) throw error;
      fail('unavailable','lyrics network request failed');
    }
    check();
    const status=result.status;
    if(allowed.length && !allowed.includes(status)) fail(options.unavailableErrors ? 'unavailable' : statusKind(status),`HTTP ${status}`);
    if(status!==200 && allowed.length) return {status,body:''};
    const body=String(result.body ?? '');
    if(BufferByteLength(body)>request.maxBytes) fail(options.unavailableErrors ? 'unavailable' : 'other','response body exceeds lyrics limit');
    return {status,body};
  }
  // No Node Buffer dependency: the source can later be bundled into QuickJS.
  function BufferByteLength(text) {
    let size=0; for(const c of text) { const n=c.codePointAt(0); size+=n<128 ? 1 : n<2048 ? 2 : n<65536 ? 3 : 4; } return size;
  }
  async function json(response,kind,complete=true) { return call('decode',kind,response.body,complete); }
  async function text(raw,provider,source=provider) {
    const result=await call('fromText',raw,provider,source);
    if(!usable(result)) fail('not_found',`no lyrics found on ${provider}`);
    return result;
  }
  async function proxy(endpoint,params) {
    const result=await get(endpoint,params,{allowed:[]});
    const raw=result.body.trim(),error=payloadError(raw);
    if(error) fail(missed(error) ? 'not_found' : 'unavailable',error);
    if(result.status!==200) fail('unavailable',`HTTP ${result.status}`);
    if(!raw) fail('unavailable','empty response');
    return raw;
  }
  async function match(title,artist,duration,request,decorated=false) {
    return await call('titlesMatch',title,request.track,decorated) &&
      await call('artistsMatch',artist,request.artist) && await call('durationMatches',duration,request.duration);
  }
  async function select(values,request,fields) {
    let best=null,bestScore=-1;
    for(const value of values || []) {
      check(); const f=await fields(value);
      if(!f.allowed) continue;
      const score=await call('score',f.title,f.artist,f.duration,request.track,request.artist,request.duration);
      if(score>bestScore) { best=value; bestScore=score; }
    }
    return best;
  }
  return {host,core,check,call,get,json,text,proxy,match,select};
}
module.exports={ids,defaults,browserUA,LyricsError,fail,statusKind,classify,payloadError,usable,retryable,spotifyId,deezerId,i64,createContext};
