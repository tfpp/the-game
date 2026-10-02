// With ceiling_tiles.bbmodel open, call exportCeilingTiles(repositoryRoot).
async function exportCeilingTiles(root) {
  const fs=require('fs');
  const source=root+'/docs/design/model-sources/ceiling-tiles/';
  const output=root+'/game/assets/room_kits/ceiling_tiles/';
  fs.writeFileSync(source+'ceiling_tiles.bbmodel',Codecs.project.compile());
  const model=JSON.parse(await Codecs.gltf.compile({scale:16,encoding:'ascii',embed_textures:true,animations:false}));
  model.images.forEach(i=>i.uri='ceiling_tiles_albedo.png');
  model.samplers.forEach(s=>{s.magFilter=9728;s.minFilter=9984;});
  model.materials.forEach(m=>{m.doubleSided=false;m.pbrMetallicRoughness.metallicFactor=0;m.pbrMetallicRoughness.roughnessFactor=.72;});
  fs.writeFileSync(output+'ceiling_tiles.gltf',JSON.stringify(model));
  fs.writeFileSync(output+'ceiling_tiles_albedo.png',Buffer.from(Texture.all[0].source.split(',')[1],'base64'));
  const faces=Outliner.elements.flatMap(mesh=>Object.values(mesh.faces).map(f=>({mesh:mesh.name,points_m:f.vertices.map(k=>mesh.vertices[k].map(v=>v/16)),uv_pixels:f.vertices.map(k=>f.uv[k])})));
  fs.writeFileSync(source+'uv_manifest.json',JSON.stringify({texture:[128,64],texels_per_metre:60,faces},null,2));
  Project.save_path=source+'ceiling_tiles.bbmodel';Project.saved=true;
  return {meshes:model.meshes.length,materials:model.materials.length};
}
