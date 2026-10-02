// Run in an empty Generic Model project. Geometry: metres * 16.
(() => {
  if (Format.id !== 'free' || Outliner.elements.length) throw new Error('Use an empty Generic Model project');
  const elements = [], textures = [], manifest = [];
  Undo.initEdit({elements, textures, outliner: true});
  Project.texture_width = 128; Project.texture_height = 64;
  const canvas = document.createElement('canvas');
  canvas.width = 128; canvas.height = 64;
  const ctx = canvas.getContext('2d');
  for (let y=0; y<64; y++) for (let x=0; x<128; x++) {
    const basic = x >= 64;
    const px = Math.max(2,Math.min(61,x%64));
    const py = Math.max(2,Math.min(61,y));
    const broad = Math.sin(Math.floor(px/6)*1.3+Math.floor(py/7)*.8)*3;
    const edge = px < 3 || px > 60 || py < 3 || py > 60;
    const tone = broad - (edge ? 16 : 0);
    const base = basic ? [165,148,120] : [180,174,153];
    ctx.fillStyle = `rgb(${base.map(v=>Math.round(v+tone)).join(',')})`;
    ctx.fillRect(x,y,1,1);
  }
  // Quiet square bead molding and a stylized pressed floral rosette.
  function emboss(path) {
    ctx.lineWidth = 1;
    ctx.save(); ctx.translate(-.5,-.5); ctx.strokeStyle='#d3cbb1'; path(); ctx.stroke(); ctx.restore();
    ctx.save(); ctx.translate(.5,.5); ctx.strokeStyle='#8e8976'; path(); ctx.stroke(); ctx.restore();
  }
  for (const r of [26,23,19]) emboss(()=>{ctx.beginPath();ctx.rect(32-r,32-r,r*2,r*2);});
  emboss(()=>{
    ctx.beginPath();
    for(let i=0;i<=64;i++) {
      const a=i/64*Math.PI*2, r=8+2*Math.cos(a*8);
      const x=32+Math.cos(a)*r,y=32+Math.sin(a)*r;
      if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);
    }
    ctx.closePath();
  });
  emboss(()=>{ctx.beginPath();ctx.arc(32,32,3,0,Math.PI*2);});
  for(let i=0;i<4;i++) {
    ctx.save(); ctx.translate(32,32);ctx.rotate(i*Math.PI/2);
    emboss(()=>{ctx.beginPath();ctx.moveTo(0,-11);ctx.bezierCurveTo(-12,-13,-12,-23,-5,-22);ctx.bezierCurveTo(0,-21,-2,-17,-5,-18);ctx.moveTo(0,-11);ctx.bezierCurveTo(12,-13,12,-23,5,-22);ctx.bezierCurveTo(0,-21,2,-17,5,-18);});
    ctx.restore();
  }
  // Extrude the two-pixel island edges into padding after painting.
  const pixels=ctx.getImageData(0,0,128,64);
  for(let y=0;y<64;y++)for(let x=0;x<128;x++) {
    const origin=x<64?0:64;
    const sx=origin+Math.max(2,Math.min(61,x-origin)),sy=Math.max(2,Math.min(61,y));
    if(sx===x&&sy===y)continue;
    const dst=(y*128+x)*4,src=(sy*128+sx)*4;
    for(let k=0;k<4;k++)pixels.data[dst+k]=pixels.data[src+k];
  }
  ctx.putImageData(pixels,0,0);
  const tex=new Texture({name:'ceiling_tiles_albedo.png',width:128,height:64,uv_width:128,uv_height:64}).fromDataURL(canvas.toDataURL()).add(false);
  textures.push(tex);
  let count=0;
  function quad(mesh,name,points,offset) {
    const keys=points.map(p=>{const k='v'+count++;mesh.vertices[k]=p.map(v=>v*16);return k;});
    const uv=points.map(p=>[offset+2+(p[0]+.5)*60,2+(p[2]+.5)*60]);
    mesh.addFaces(new MeshFace(mesh,{vertices:keys,uv:Object.fromEntries(keys.map((k,i)=>[k,uv[i]])),texture:tex.uuid}));
    manifest.push({mesh:mesh.name,name,points_m:points,uv_pixels:uv});
  }
  const tin=new Mesh({name:'TinCeilingTile',vertices:{},faces:{},origin:[0,0,0]}).init();elements.push(tin);
  const rings=[[.5,0],[.475,0],[.455,-.012],[.425,-.012],[.405,0]];
  const corners=(r,y)=>[[-r,y,-r],[r,y,-r],[r,y,r],[-r,y,r]];
  for(let n=0;n<rings.length-1;n++) {
    const outer=corners(...rings[n]),inner=corners(...rings[n+1]);
    for(let i=0;i<4;i++)quad(tin,'pressed_border_'+n+'_'+i,[outer[i],outer[(i+1)%4],inner[(i+1)%4],inner[i]],0);
  }
  quad(tin,'floral_field',corners(.405,0),0);
  const basic=new Mesh({name:'BasicCeilingTile',vertices:{},faces:{},origin:[20,0,0]}).init();elements.push(basic);
  quad(basic,'plaster_field',corners(.5,0),64);
  globalThis.ceilingManifest=manifest;
  tin.select();Canvas.updateAll();Undo.finishEdit('Create pressed tin and plain plaster ceiling tiles');
  return {tin_triangles:34,basic_triangles:2,texture:[128,64],footprint_m:[1,1],face:'-Y'};
})()
