// Run in Blockbench's JavaScript context with an empty Generic Model project.
// Dimensions below are metres; Blockbench geometry uses 16 units per metre.
(() => {
  if (Format.id !== 'free' || Outliner.elements.length) throw new Error('Use an empty Generic Model project');
  const elements = [];
  Undo.initEdit({elements, textures: [], outliner: true});
  Project.texture_width = 64;
  Project.texture_height = 128;
  const canvas = document.createElement('canvas');
  canvas.width = 64; canvas.height = 128;
  const ctx = canvas.getContext('2d');
  for (let y=0; y<128; y++) for(let x=0;x<64;x++) {
    ctx.fillStyle = ((Math.floor(x/4)+Math.floor(y/4))%2) ? '#c6b5a1' : '#54473d';
    ctx.fillRect(x,y,1,1);
  }
  const tex = new Texture({name:'wood_panel_wall_albedo.png',width:64,height:128,uv_width:64,uv_height:128}).fromDataURL(canvas.toDataURL()).add(false);
  const mesh = new Mesh({name:'WoodPanelWall',vertices:{},faces:{},origin:[0,0,0]}).init();
  elements.push(mesh);
  let index=0;
  const manifest=[];
  function quad(name, points, mode='vertical') {
    const keys = points.map(p => {const k='v'+index++; mesh.vertices[k]=p.map(v=>v*16); return k;});
    let uv;
    if(mode==='vertical') uv=points.map(p=>[4+(p[0]+.5)*48,124-p[1]*48]);
    else if(mode==='side') uv=points.map(p=>[4+(p[2]+.1)*48,124-p[1]*48]);
    else if(mode==='cap') uv=points.map(p=>[4+(p[0]+.5)*48,4+(p[2]+.1)*48]);
    else {const y0=Math.min(...points.map(p=>p[1]));uv=points.map(p=>[4+(p[1]-y0)*48,4+(p[0]+.5)*48]);}
    mesh.addFaces(new MeshFace(mesh,{vertices:keys,uv:Object.fromEntries(keys.map((k,i)=>[k,uv[i]])),texture:tex.uuid}));
    manifest.push({name,points,uv,grain:mode});
  }
  function front(name,x0,x1,y0,y1,z0,z1=z0,mode='vertical') {
    quad(name,[[x0,y0,z0],[x1,y0,z0],[x1,y1,z1],[x0,y1,z1]],mode);
  }
  function panel(name,x0,x1,y0,y1,border,bevel) {
    const a=x0+border,b=x1-border,c=y0+border,d=y1-border;
    front(name+'_bottom',x0,x1,y0,c,.06,.06,'horizontal');
    front(name+'_top',x0,x1,d,y1,.06,.06,'horizontal');
    front(name+'_left',x0,a,c,d,.06);
    front(name+'_right',b,x1,c,d,.06);
    const outer=[[a,c,.06],[b,c,.06],[b,d,.06],[a,d,.06]];
    const inner=[[a+bevel,c+bevel,.04],[b-bevel,c+bevel,.04],[b-bevel,d-bevel,.04],[a+bevel,d-bevel,.04]];
    for(let i=0;i<4;i++) {const j=(i+1)%4;quad(name+'_bevel_'+i,[outer[i],outer[j],inner[j],inner[i]]);}
    quad(name+'_inset',inner);
  }
  const profile=[[0,.1],[.12,.1],[.16,.06],[.78,.06],[.80,.1],[.84,.1],[.86,.06],[2.36,.06],[2.40,.1],[2.5,.1]];
  for(let i=0;i<profile.length-1;i++) {
    const [y0,z0]=profile[i], [y1,z1]=profile[i+1];
    if(i===2) {panel('lower_left',-.5,0,y0,y1,.05,.015);panel('lower_right',0,.5,y0,y1,.05,.015);}
    else if(i===6) panel('upper',-.5,.5,y0,y1,.06,.02);
    else front('rail_'+i,-.5,.5,y0,y1,z0,z1,'horizontal');
    quad('right_end_'+i,[[.5,y0,z0],[.5,y0,-.1],[.5,y1,-.1],[.5,y1,z1]],'side');
    quad('left_end_'+i,[[-.5,y0,-.1],[-.5,y0,z0],[-.5,y1,z1],[-.5,y1,-.1]],'side');
  }
  mesh.select();
  Canvas.updateAll();
  Undo.finishEdit('Create low-poly wood panel wall');
  globalThis.wallManifest=manifest;
  return {quads:manifest.length,triangles:manifest.length*2,mesh:mesh.uuid,texture:tex.uuid};
})()
