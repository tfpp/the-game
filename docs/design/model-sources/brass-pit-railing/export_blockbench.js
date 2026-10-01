// Run with brass_pit_railing.bbmodel open in Blockbench, then call exportPitRailing(root).
async function exportPitRailing(root) {
  const fs = require('fs');
  const source = root + '/docs/design/model-sources/brass-pit-railing/';
  const output = root + '/game/assets/room_kits/brass_pit_railing/';
  fs.writeFileSync(source + 'brass_pit_railing.bbmodel', Codecs.project.compile());
  const model = JSON.parse(await Codecs.gltf.compile({scale:16, encoding:'ascii', embed_textures:true, animations:false}));
  for (const image of model.images) image.uri = 'aged_brass_palette.png';
  for (const sampler of model.samplers) {
    sampler.magFilter = 9728;
    sampler.minFilter = 9984;
  }
  for (const material of model.materials) {
    material.name = 'WalnutAndGoldBrass';
    material.doubleSided = false;
    material.pbrMetallicRoughness.metallicFactor = 0;
    material.pbrMetallicRoughness.roughnessFactor = 0.6;
  }
  fs.writeFileSync(output + 'brass_pit_railing.gltf', JSON.stringify(model));
  fs.writeFileSync(output + 'aged_brass_palette.png', Buffer.from(Texture.all[0].source.split(',')[1], 'base64'));
  Project.save_path = source + 'brass_pit_railing.bbmodel';
  Project.saved = true;
  return {meshes:model.meshes.length, materials:model.materials.length};
}
