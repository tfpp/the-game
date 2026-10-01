// With beige_stucco_wall.bbmodel open, call exportBeigeStuccoWall(repositoryRoot).
async function exportBeigeStuccoWall(root) {
  const fs=require('fs');
  const source=root+'/docs/design/model-sources/beige-stucco-wall/';
  const output=root+'/game/assets/room_kits/beige_stucco_wall/';
  fs.writeFileSync(source+'beige_stucco_wall.bbmodel',Codecs.project.compile());
  const model=JSON.parse(await Codecs.gltf.compile({scale:16,encoding:'ascii',embed_textures:true,animations:false}));
  model.images.forEach(i=>i.uri='beige_stucco_wall_albedo.png');
  model.samplers.forEach(s=>{s.magFilter=9728;s.minFilter=9984;});
  model.materials.forEach(m=>{m.doubleSided=false;m.pbrMetallicRoughness.metallicFactor=0;m.pbrMetallicRoughness.roughnessFactor=.95;});
  fs.writeFileSync(output+'beige_stucco_wall.gltf',JSON.stringify(model));
  fs.writeFileSync(output+'beige_stucco_wall_albedo.png',Buffer.from(Texture.all[0].source.split(',')[1],'base64'));
  const mesh=Outliner.elements[0];
  const manifest=JSON.parse(fs.readFileSync(source+'uv_manifest.json','utf8'));
  manifest.faces=Object.entries(mesh.faces).map(([name,f])=>({name,points_m:f.vertices.map(k=>mesh.vertices[k].map(v=>v/16)),uv_pixels:f.vertices.map(k=>f.uv[k])}));
  fs.writeFileSync(source+'uv_manifest.json',JSON.stringify(manifest,null,2));
  Project.save_path=source+'beige_stucco_wall.bbmodel';Project.saved=true;
  return {meshes:model.meshes.length,materials:model.materials.length};
}
