#!/usr/bin/env node
// SPDX-License-Identifier: LGPL-3.0-only
// Import a closed set of upstream declarations, without registering full providers.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const acorn = require('acorn');
const eslintScope = require('eslint-scope');

const upstream = path.resolve(process.argv[2] || '');
if (!process.argv[2] || !fs.existsSync(path.join(upstream, 'registry.json'))) {
  throw new Error('Usage: node extensions/tools/extract.cjs /path/to/Mornye-Extension');
}
const destination = path.resolve(__dirname, '..');
const revision = cp.execFileSync('git', ['-C', upstream, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
if (cp.execFileSync('git', ['-C', upstream, 'status', '--porcelain'], {encoding: 'utf8'}).trim()) {
  throw new Error('Upstream checkout must be clean');
}
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const inventory = [];
const directories = fs.readdirSync(path.join(upstream, 'sources')).sort().filter(id => id !== 'jellyfin');
for (const id of directories) {
  const sourcePath = `sources/${id}/index.js`;
  const original = fs.readFileSync(path.join(upstream, sourcePath), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.join(upstream, 'sources', id, 'manifest.json'), 'utf8'));
  const ast = acorn.parse(original, {ecmaVersion: 2022, ranges: true, locations: true});
  const scope = eslintScope.analyze(ast, {ecmaVersion: 2022, optimistic: true, ignoreEval: true});
  let body = ast.body;
  // Beatport keeps its declarations in a single immediately invoked function.
  const iife = body.find(n => n.type === 'ExpressionStatement' && n.expression.type === 'CallExpression'
    && n.expression.callee.type === 'FunctionExpression');
  if (iife) body = iife.expression.callee.body.body;
  const registration = body.find(n => n.type === 'ExpressionStatement' && n.expression.type === 'CallExpression'
    && n.expression.callee.name === 'registerExtension');
  if (!registration) throw new Error(`${id}: missing static registration`);
  const properties = new Map(registration.expression.arguments[0].properties.map(p => [p.key.name || p.key.value, p.value]));
  if (!properties.has('getArtist')) throw new Error(`${id}: missing artist entry point`);
  const declarations = body.filter(n => ['VariableDeclaration', 'FunctionDeclaration'].includes(n.type));
  const references = scope.scopes.flatMap(s => s.references);
  const inside = (node, range) => node.start >= range.start && node.end <= range.end;
  const selected = new Set();
  const visited = new Set();
  function include(node) {
    if (visited.has(node)) return;
    visited.add(node);
    for (const reference of references.filter(r => inside(r.identifier, node))) {
      if (!reference.resolved) continue;
      for (const def of reference.resolved.defs) {
        const declaration = declarations.find(d => inside(def.node, d));
        if (declaration && !selected.has(declaration)) {
          selected.add(declaration);
          include(declaration);
        }
      }
    }
  }
  const roots = ['initialize', 'cleanup', 'getArtist'];
  if (id === 'apple-music') roots.push('getAlbum', 'fetchLyrics');
  const aliases = [];
  for (const name of roots) {
    const expression = properties.get(name);
    if (!expression) continue;
    include(expression);
    aliases.push(`var __upstream_${name} = ${original.slice(expression.start, expression.end)};`);
  }
  const ordered = [...selected].sort((a,b) => a.start-b.start);
  const spans = [...ordered, ...roots.map(name => properties.get(name)).filter(Boolean)];
  const globals = [...new Set(scope.globalScope.through
    .filter(r => spans.some(span => inside(r.identifier, span)))
    .map(r => r.identifier.name))].sort();
  // The original declarations stay intact. Only the host-facing registration is new.
  const adapter = `
function __artworkOnly(value) {
  if (!value || typeof value !== "object") return value;
  if (value.success === false || value.error) return value;
  var item = value.artist_info || value.album_info || value.artist || value.album || value;
  var output = {};
  ["id", "name", "image_url", "images", "cover_url", "header_image", "header_video", "header_logo"].forEach(function(key) {
    if (typeof item[key] !== "undefined") output[key] = item[key];
  });
  return output;
}
var __internalSource = {
  getArtistArtwork: function(id) { return __artworkOnly(__upstream_getArtist(id)); }
};
${properties.has('initialize') ? '__internalSource.initialize = __upstream_initialize;' : ''}
${properties.has('cleanup') ? '__internalSource.cleanup = __upstream_cleanup;' : ''}
${id === 'apple-music' ? '__internalSource.getAlbumArtwork = function(id) { return __artworkOnly(__upstream_getAlbum(id)); };\n__internalSource.fetchLyrics = __upstream_fetchLyrics;' : ''}
registerExtension(__internalSource);
`;
  const output = `// SPDX-License-Identifier: LGPL-3.0-only\n// Extracted from https://github.com/mornyeapp/Mornye-Extension\n// Upstream ${revision} / ${sourcePath}\n// Inactive source import: no app integration or update trust policy is installed.\n\n`
    + ordered.map(n => original.slice(n.start, n.end)).join('\n\n') + '\n\n'
    + aliases.join('\n') + '\n' + adapter;
  const target = path.join(destination, 'sources', id);
  fs.mkdirSync(target, {recursive:true});
  fs.writeFileSync(path.join(target, 'index.js'), output);
  const metadata = {
    id, upstream_version: manifest.version,
    upstream_repository: 'https://github.com/mornyeapp/Mornye-Extension', upstream_commit: revision,
    upstream_path: sourcePath, upstream_sha256: hash(original), extracted_sha256: hash(output),
    capabilities: id === 'apple-music' ? ['artist_artwork','motion_artwork','lyrics'] : ['artist_artwork'],
    exported_methods: ['getArtistArtwork', ...roots.filter(n => ['initialize','cleanup'].includes(n) && properties.has(n)),
      ...(id === 'apple-music' ? ['getAlbumArtwork','fetchLyrics'] : [])].sort(),
    retained_declarations: ordered.map(n => ({
      names: n.type === 'FunctionDeclaration' ? [n.id.name] : n.declarations.map(d => original.slice(d.id.start, d.id.end)),
      upstream_start_line: n.loc.start.line, upstream_end_line: n.loc.end.line,
    })),
    referenced_globals: globals,
    upstream_permissions: manifest.permissions || {},
    upstream_settings: manifest.settings || [],
    integration_status: 'source-only; not installed or loaded by the app',
  };
  fs.writeFileSync(path.join(target, 'source.json'), JSON.stringify(metadata,null,2)+'\n');
  inventory.push({id, version: manifest.version, capabilities: metadata.capabilities,
    declarations: ordered.length, upstream_sha256: hash(original), extracted_sha256: hash(output)});
}
for (const filename of ['LICENSE','COPYING','NOTICE']) {
  fs.copyFileSync(path.join(upstream,filename),path.join(destination,filename));
}
fs.writeFileSync(path.join(destination,'upstream-lock.json'),JSON.stringify({
  upstream_repository:'https://github.com/mornyeapp/Mornye-Extension',upstream_commit:revision,
  excluded_providers:['jellyfin'],providers:inventory,
},null,2)+'\n');
console.log(`Imported ${inventory.length} source subsets from ${revision}; Jellyfin excluded.`);
