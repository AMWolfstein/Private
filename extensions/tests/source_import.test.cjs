// SPDX-License-Identifier: LGPL-3.0-only
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const acorn = require('acorn');
const eslintScope = require('eslint-scope');
const root = path.join(__dirname, '..');
const lock = JSON.parse(fs.readFileSync(path.join(root, 'upstream-lock.json')));
const expected = ['amazon','apple-music','beatport','bugs-music','deezer','genie-music','jiosaavn',
  'melon-music','qobuz-web','soundcloud','spotify-web','tidal-web','ytmusic-spotiflac'];
const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
function load(id, extra = {}) {
  let api;
  const context = vm.createContext({
    registerExtension(value) { api = value; },
    log: {info(){},warn(){},debug(){},error(){}}, ...extra,
  });
  const source = fs.readFileSync(path.join(root, 'sources', id, 'index.js'), 'utf8');
  vm.runInContext(source, context, {timeout:1000});
  return {api, context, source};
}

test('all source-backed artist providers except Jellyfin are inventoried', () => {
  assert.deepEqual(lock.providers.map(p=>p.id), expected);
  assert.deepEqual(fs.readdirSync(path.join(root,'sources')).sort(),expected);
  assert.deepEqual(lock.excluded_providers,['jellyfin']);
});

for (const id of expected) {
  test(`${id}: loads without network or file access and registers only selected operations`, () => {
    const {api,source}=load(id);
    const metadata=JSON.parse(fs.readFileSync(path.join(root,'sources',id,'source.json')));
    assert.deepEqual(Object.keys(api).sort(),metadata.exported_methods);
    for(const key of Object.keys(api)) {
      assert.ok(['initialize','cleanup','getArtistArtwork','getAlbumArtwork','fetchLyrics'].includes(key),key);
      assert.equal(typeof api[key],'function');
    }
    assert.equal(typeof api.getArtistArtwork,'function');
    assert.equal('download' in api,false);
    assert.equal('customSearch' in api,false);
    assert.equal('getHomeFeed' in api,false);
    assert.equal('handleUrl' in api,false);
    assert.equal('getTrack' in api,false);
    assert.doesNotMatch(source,/\bfile\s*\.\s*download\s*\(/);
    assert.equal(sha256(source),metadata.extracted_sha256);
    assert.equal(metadata.extracted_sha256,lock.providers.find(p=>p.id===id).extracted_sha256);
    assert.equal(metadata.upstream_commit,lock.upstream_commit);
    assert.equal(metadata.upstream_sha256,lock.providers.find(p=>p.id===id).upstream_sha256);
  });
  test(`${id}: dependency extraction introduces no unresolved helper names`, () => {
    const {source}=load(id);
    const metadata=JSON.parse(fs.readFileSync(path.join(root,'sources',id,'source.json')));
    const ast=acorn.parse(source,{ecmaVersion:2022,ranges:true});
    const scope=eslintScope.analyze(ast,{ecmaVersion:2022,optimistic:true,ignoreEval:true});
    const permitted=new Set([...metadata.referenced_globals,'registerExtension']);
    const missing=[...new Set(scope.globalScope.through.map(r=>r.identifier.name))].filter(name=>!permitted.has(name));
    assert.deepEqual(missing,[]);
  });
}

test('Apple artist artwork adapter retains portrait, motion and logo without catalog output',()=>{
  const {api,context}=load('apple-music');
  context.apiGet=()=>({data:[{id:'artist-1',attributes:{name:'Artist',
    artwork:{url:'https://example.test/portrait/{w}x{h}.jpg'},
    editorialVideo:{motionArtistSquare1x1:{video:'https://example.test/motion.m3u8'}},
  }}]});
  const result=JSON.parse(JSON.stringify(api.getArtistArtwork('artist-1')));
  assert.equal(result.name,'Artist');
  assert.match(result.image_url,/portrait/);
  assert.equal(result.header_video,'https://example.test/motion.m3u8');
  assert.equal('albums' in result,false);
  assert.equal('top_tracks' in result,false);
  assert.equal('concerts' in result,false);
});

test('Apple album artwork adapter keeps motion and drops track list',()=>{
  const {api,context}=load('apple-music');
  context.apiGet=()=>({data:[{id:'1',attributes:{name:'Album',trackCount:0,
    artwork:{url:'https://example.test/cover/{w}x{h}.jpg'},
    editorialVideo:{motionDetailTall:{video:'https://example.test/cover.m3u8'}},
  },relationships:{tracks:{data:[]},artists:{data:[]}}}]});
  const result=JSON.parse(JSON.stringify(api.getAlbumArtwork('1')));
  assert.equal(result.header_video,'https://example.test/cover.m3u8');
  assert.equal('track_list' in result,false);
  assert.equal('tracks' in result,false);
});

test('Apple lyrics skip requests without the user token required upstream',()=>{
  const {api}=load('apple-music', {http:{get(){throw new Error('Unexpected HTTP request');}}});
  assert.equal(api.fetchLyrics('Song','Artist','Album',180),null);
});

for (const fallback of [false,true]) {
  test(`Apple lyrics fetch and parse timed TTML${fallback ? ' with standard-lyrics fallback' : ''}`,()=>{
    const {api,context}=load('apple-music');
    api.initialize({mediaUserToken:'fixture-token'});
    context.findTrackId=()=> 'song-1';
    const calls=[];
    context.apiGetWithUserToken=route=>{
      calls.push(route);
      if (fallback && route.endsWith('/syllable-lyrics')) return {data:[]};
      return {data:[{attributes:{ttml:'<tt itunes:timing="Line"><body><div><p begin="0s" end="2s">First</p><p begin="3s" end="5s">Second</p></div></body></tt>'}}]};
    };
    const result=api.fetchLyrics('Song','Artist','Album',180);
    assert.equal(result.syncType,'LINE_SYNCED');
    assert.deepEqual(Array.from(result.lines,line=>line.words),['First','Second']);
    assert.deepEqual(calls,fallback ? ['songs/song-1/syllable-lyrics','songs/song-1/lyrics'] : ['songs/song-1/syllable-lyrics']);
  });
}

test('Beatport artist artwork retains provider identity and drops releases',()=>{
  const {api}=load('beatport',{session:{signedFetch(method,url,body){
    assert.equal(method,'POST');assert.equal(url,'/btp/catalog');
    if(body.action==='artist') return {statusCode:200,body:JSON.stringify({id:42,name:'Artist',image:'https://example.test/artist.jpg'})};
    return {statusCode:200,body:JSON.stringify({results:[]})};
  }}});
  const result=JSON.parse(JSON.stringify(api.getArtistArtwork('42')));
  assert.equal(result.id,'beatport:42');
  assert.equal(result.image_url,'https://example.test/artist.jpg');
  assert.equal('albums' in result,false);
});
