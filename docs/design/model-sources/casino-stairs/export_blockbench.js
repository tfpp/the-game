async function exportCasinoStairs(root) {
  const fs=require('fs'),source=root+'/docs/design/model-sources/casino-stairs/',out=root+'/game/assets/room_kits/casino_stairs/';
  fs.writeFileSync(source+'casino_stair_module.bbmodel',Codecs.project.compile());
  const model=JSON.parse(await Codecs.gltf.compile({scale:16,encoding:'ascii',embed_textures:true,animations:false}));
  model.images.forEach(i=>i.uri='casino_stairs_albedo.png');model.samplers.forEach(s=>{s.magFilter=9728;s.minFilter=9984;});
  model.materials.forEach(m=>{m.doubleSided=false;m.pbrMetallicRoughness.metallicFactor=0;m.pbrMetallicRoughness.roughnessFactor=.95;});
  fs.writeFileSync(out+'casino_stair_module.gltf',JSON.stringify(model));
  fs.writeFileSync(out+'casino_stairs_albedo.png',Buffer.from(Texture.all[0].source.split(',')[1],'base64'));
  fs.writeFileSync(source+'uv_manifest.json',JSON.stringify(globalThis.casinoStairManifest,null,2));
  const guide=document.createElement('canvas');guide.width=64;guide.height=64;const g=guide.getContext('2d');g.fillStyle='#29262a';g.fillRect(0,0,64,64);
  for(const {rect:[u,v,w,h]} of globalThis.casinoStairManifest.islands){g.fillStyle='#b69f7e';g.fillRect(u,v,w,h);g.strokeStyle='#fff0db';g.strokeRect(u,v,w,h);}
  fs.writeFileSync(source+'uv_template.png',Buffer.from(guide.toDataURL().split(',')[1],'base64'));
  Project.save_path=source+'casino_stair_module.bbmodel';Project.saved=true;
  return {meshes:model.meshes.length,materials:model.materials.length};
}
