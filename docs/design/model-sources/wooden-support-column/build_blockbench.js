// Run in a new, empty Blockbench Generic Model project.
// One wall unit = 5 metres; 16 Blockbench units per metre.
(() => {
  if (Format.id !== 'free' || Outliner.elements.length) throw new Error('Use an empty Generic Model project');
  const elements = [], textures = [];
  Undo.initEdit({elements, textures, outliner: true});
  Project.texture_width = 32; Project.texture_height = 128;
  const canvas = document.createElement('canvas');
  canvas.width = 32; canvas.height = 128;
  const ctx = canvas.getContext('2d');
  // Original coarse walnut grain and quiet padded gold palette.
  for (let y = 0; y < 128; y++) for (let x = 0; x < 32; x++) {
    const px = Math.max(12, Math.min(31, x));
    const py = Math.max(4, Math.min(124, y));
    const seam = px <= 13 || px >= 30;
    const grain = Math.sin(px * 1.7 + Math.sin(py * .095) * .65) * 7;
    const broad = Math.sin(Math.floor(py / 8) * .7 + px * .3) * 3;
    const shade = seam ? -16 : grain + broad;
    const rgb = x < 8 ? [177, 126, 48] : x < 12 ? [69, 38, 22] : [82 + shade, 43 + shade * .6, 25 + shade * .35];
    ctx.fillStyle = `rgb(${rgb.map(Math.round).join(',')})`;
    ctx.fillRect(x, y, 1, 1);
  }
  const tex = new Texture({name: 'wooden_support_column_albedo.png', width: 32, height: 128, uv_width: 32, uv_height: 128}).fromDataURL(canvas.toDataURL()).add(false);
  textures.push(tex);
  const mesh = new Mesh({name: 'WoodenSupportColumn', vertices: {}, faces: {}, origin: [0, 0, 0]}).init();
  elements.push(mesh);
  // Continuous exterior, no hidden box faces. Each pair selects the material
  // on the section above it. Matching endpoint widths make vertical joints flush.
  const profile = [[0,.5,'gold'],[.06,.5,'gold'],[.12,.46,'wood'],[.26,.46,'gold'],[.30,.46,'gold'],[.34,.42,'wood'],[.38,.4,'wood'],[4.62,.4,'wood'],[4.66,.42,'gold'],[4.70,.46,'gold'],[4.74,.46,'wood'],[4.88,.46,'gold'],[4.94,.5,'gold'],[5,.5,'gold']];
  let counter = 0;
  const manifest = [];
  function quad(name, points, material, side = false) {
    const keys = points.map(p => {const k = 'v' + counter++; mesh.vertices[k] = p.map(v => v * 16); return k;});
    const trim = material === 'wood' && points.some(p => Math.abs(p[0]) > .401 || Math.abs(p[2]) > .401);
    const uv = points.map(p => material === 'gold' ? [4, 64] : trim ? [10, 64] : side ? [22 + p[2] * 24, 124 - p[1] * 24] : [22 + p[0] * 24, 124 - p[1] * 24]);
    mesh.addFaces(new MeshFace(mesh, {vertices: keys, uv: Object.fromEntries(keys.map((k, i) => [k, uv[i]])), texture: tex.uuid}));
    manifest.push({name, points_m: points, uv_pixels: uv, material});
  }
  for (let i = 0; i < profile.length - 1; i++) {
    const [a, r, material] = profile[i], [b, s] = profile[i + 1];
    quad('front_' + i, [[-r,a,r],[r,a,r],[s,b,s],[-s,b,s]], material);
    quad('right_' + i, [[r,a,r],[r,a,-r],[s,b,-s],[s,b,s]], material, true);
    quad('back_' + i, [[r,a,-r],[-r,a,-r],[-s,b,-s],[s,b,-s]], material);
    quad('left_' + i, [[-r,a,-r],[-r,a,r],[-s,b,s],[-s,b,-s]], material, true);
  }
  // Caps permit standalone placement. They remain coincident and hidden at stacks.
  quad('bottom', [[-.5,0,-.5],[.5,0,-.5],[.5,0,.5],[-.5,0,.5]], 'gold');
  quad('top', [[-.5,5,.5],[.5,5,.5],[.5,5,-.5],[-.5,5,-.5]], 'gold');
  globalThis.columnManifest = manifest;
  mesh.select(); Canvas.updateAll();
  Undo.finishEdit('Create stackable walnut and gold support column');
  return {quads: manifest.length, triangles: manifest.length * 2, texture: [32,128], bounds_m: [1,5,1]};
})()
