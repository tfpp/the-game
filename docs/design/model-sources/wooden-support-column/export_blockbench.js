// Load in Blockbench with wooden_support_column.bbmodel open, then call
// exportWoodenSupportColumn(repositoryRoot).
async function exportWoodenSupportColumn(root) {
  const fs = require('fs');
  const source = root + '/docs/design/model-sources/wooden-support-column/';
  const output = root + '/game/assets/room_kits/wooden_support_column/';
  fs.writeFileSync(source + 'wooden_support_column.bbmodel', Codecs.project.compile());
  const model = JSON.parse(await Codecs.gltf.compile({scale:16, encoding:'ascii', embed_textures:true, animations:false}));
  for (const image of model.images) image.uri = 'wooden_support_column_albedo.png';
  for (const sampler of model.samplers) {sampler.magFilter = 9728; sampler.minFilter = 9984;}
  for (const material of model.materials) {
    material.doubleSided = false;
    material.pbrMetallicRoughness.metallicFactor = 0;
    material.pbrMetallicRoughness.roughnessFactor = .78;
  }
  fs.writeFileSync(output + 'wooden_support_column.gltf', JSON.stringify(model));
  fs.writeFileSync(output + 'wooden_support_column_albedo.png', Buffer.from(Texture.all[0].source.split(',')[1], 'base64'));
  const mesh = Outliner.elements[0];
  const faces = Object.values(mesh.faces).map(f => ({points_m:f.vertices.map(k=>mesh.vertices[k].map(v=>v/16)), uv_pixels:f.vertices.map(k=>f.uv[k])}));
  fs.writeFileSync(source + 'uv_manifest.json', JSON.stringify({texture:[32,128],texels_per_metre:24,faces}, null, 2));
  Project.save_path = source + 'wooden_support_column.bbmodel';
  Project.saved = true;
  return {meshes:model.meshes.length, materials:model.materials.length, triangles:faces.length*2};
}
