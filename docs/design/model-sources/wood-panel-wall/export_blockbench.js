// Run with the authoritative wood_panel_wall.bbmodel open in Blockbench.
// Pass the repository root explicitly, without a trailing slash.
async function exportWoodPanelWall(root) {
  const fs = require('fs');
  const source = root + '/docs/design/model-sources/wood-panel-wall/';
  const output = root + '/game/assets/room_kits/wood_panel_wall/';
  fs.writeFileSync(source + 'wood_panel_wall.bbmodel', Codecs.project.compile());
  const model = JSON.parse(await Codecs.gltf.compile({scale:16,encoding:'ascii',embed_textures:true,animations:false}));
  for (const material of model.materials || []) {
    material.name = 'AgedWalnut';
    material.doubleSided = false;
    material.alphaMode = 'OPAQUE';
    material.pbrMetallicRoughness.metallicFactor = 0;
    material.pbrMetallicRoughness.roughnessFactor = 0.78;
  }
  for (const image of model.images || []) image.uri = 'wood_panel_wall_albedo.png';
  for (const sampler of model.samplers || []) {
    sampler.magFilter = 9728;
    sampler.minFilter = 9984;
  }
  fs.writeFileSync(output + 'wood_panel_wall.gltf', JSON.stringify(model));
  fs.writeFileSync(output + 'wood_panel_wall_albedo.png', Buffer.from(Texture.all[0].source.split(',')[1], 'base64'));
  Project.save_path = source + 'wood_panel_wall.bbmodel';
  Project.saved = true;
  return {meshes:model.meshes.length,materials:model.materials.length,images:model.images.length,triangles:model.meshes.reduce((n,m)=>n+m.primitives.reduce((s,p)=>s+model.accessors[p.indices].count/3,0),0)};
}
