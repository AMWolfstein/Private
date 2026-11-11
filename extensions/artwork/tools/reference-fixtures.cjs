// SPDX-License-Identifier: LGPL-3.0-only
// Offline oracle: executes only pinned repository references, never fetched code.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
function source(id) {
  const context = vm.createContext({
    registerExtension() {}, log: {info(){},warn(){},error(){},debug(){}},
  });
  vm.runInContext(fs.readFileSync(path.join(root, `extensions/sources/${id}/index.js`), 'utf8'), context);
  return context;
}
const portrait = {url:'https://images.example.test/portrait/{w}x{h}.jpg'};
const square = {video:'https://images.example.test/square.m3u8', previewFrame:{url:'https://images.example.test/square/{w}x{h}.jpg',width:3840,height:3840}};
const wide = {video:'https://images.example.test/wide.m3u8', previewFrame:{url:'https://images.example.test/wide/{w}x{h}.jpg',width:3840,height:2160}};
const tall = {video:'https://images.example.test/tall.m3u8', previewFrame:{url:'https://images.example.test/tall/{w}x{h}.jpg',width:3000,height:4000}};
const cases=[];
function apple(name, kind, attributes) {
  const response={data:[{id:'42',attributes:{name:'Artist',...attributes}}]};
  const context=source('apple-music');context.apiGet=()=>JSON.parse(JSON.stringify(response));
  const result=kind==='artist'?context.getArtist('42'):context.getAlbum('42');
  assert.ok(result, name);
  const item={name,provider:'apple-music',kind,id:'42',response,expected:JSON.parse(JSON.stringify(context.__artworkOnly(result)))};
  if(kind==='album')item.expected_metadata=JSON.parse(JSON.stringify({
    editorial_notes:result.editorial_notes,genre:result.genre,release_date:result.release_date,
    label:result.label,copyright:result.copyright,
  }));
  cases.push(item);
}
apple('artist portrait','artist',{artwork:portrait});
apple('artist no image is valid','artist',{});
apple('artist square motion before wide','artist',{artwork:portrait,editorialVideo:{motionArtistSquare1x1:square,motionArtistFullscreen16x9:wide}});
apple('artist widescreen fallback','artist',{artwork:portrait,editorialVideo:{motionArtistWide16x9:wide}});
apple('artist editorial still before preview','artist',{artwork:portrait,editorialArtwork:{vipSquare:{url:'https://images.example.test/editorial/{w}x{h}.jpg'}},editorialVideo:{motionArtistWide16x9:wide}});
apple('artist preview only keeps aspect','artist',{editorialVideo:{motionArtistFullscreen16x9:wide}});
apple('preview prefers explicit dimensions over aliases','artist',{editorialVideo:{motionArtistWide16x9:{video:wide.video,previewFrame:{url:wide.previewFrame.url,width:600,height:300,w:3000,h:4000}}}});
apple('artist logo remains transparent','artist',{artwork:portrait,editorialArtwork:{musicContentColorLogoTrimmed:{url:'https://images.example.test/logo/{w}x{h}bb.jpg?x=1',width:2400,height:600}}});
apple('artist invalid logo dimensions','artist',{editorialArtwork:{musicContentColorLogoTrimmed:{url:'https://images.example.test/logo.jpg',width:0,height:600}}});
apple('artwork size clamped','artist',{artwork:{url:portrait.url,width:10000,height:10000}});
apple('album tall motion and square cover','album',{artwork:portrait,editorialVideo:{motionDetailTall:tall,motionDetailSquare:square},genreNames:['Music','Pop','pop','Arabic'],releaseDate:'2025-07-03',recordLabel:'Label',copyright:'Copyright',editorialNotes:{standard:'Album description'}});
apple('album square motion excluded from video','album',{artwork:portrait,editorialVideo:{motionDetailSquare:square}});
apple('album wide preview without wide video','album',{artwork:portrait,editorialVideo:{motionDetailWide:wide}});
apple('album plain cover','album',{artwork:portrait});
apple('album logo never becomes cover','album',{editorialArtwork:{musicContentColorLogoTrimmed:{url:portrait.url,width:100,height:20}}});
for(const [name,response] of [
 ['artist picture precedence',{id:42,name:'Artist',picture_xl:'https://images.example.test/large.jpg',picture:'https://images.example.test/small.jpg'}],
 ['artist picture resize',{id:42,name:'Artist',picture:'https://e-cdns-images.dzcdn.net/images/artist/abc/250x250-000000-80-0-0.jpg'}],
 ['artist large picture retained',{id:'42',name:'Artist',picture_xl:'https://e-cdns-images.dzcdn.net/images/artist/abc/1600x1600-000000-80-0-0.jpg'}],
 ['artist cover fallback',{id:42,name:'Artist',cover_big:'https://images.example.test/fallback.jpg'}],
 ['artist missing image',{id:42,name:'Artist'}],
]){
 const context=source('deezer');cases.push({name,provider:'deezer',kind:'artist',id:'42',response,expected:JSON.parse(JSON.stringify(context.__artworkOnly(context.formatArtist(response))))});
}
const output=JSON.parse(JSON.stringify({source_revision:'12530ceda46dc78a10f9258b7d65a71452dfcf50',cases}));
const file=path.join(root,'extensions/artwork/fixtures/apple-deezer.json');
if(process.argv.includes('--write'))fs.writeFileSync(file,JSON.stringify(output,null,2)+'\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(file,'utf8')),output);
console.log(`${cases.length} pinned Apple/Deezer artwork fixtures ${process.argv.includes('--write')?'written':'verified'}`);
