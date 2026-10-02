// Run in a new empty Generic Model project. One full of a 5 m wall.
(() => {
  if(Format.id!=='free'||Outliner.elements.length)throw new Error('Use an empty Generic Model project');
  const elements=[],textures=[];
  Undo.initEdit({elements,textures,outliner:true});
  Project.texture_width=64;Project.texture_height=128;
  const canvas=document.createElement('canvas');canvas.width=64;canvas.height=128;
  const ctx=canvas.getContext('2d');ctx.fillStyle='#b69f7e';ctx.fillRect(0,0,64,128);
  const islands=[{name:'front_back',rect:[2,2,24,120]},{name:'ends',rect:[32,2,4.8,120]},{name:'caps',rect:[44,2,4.8,24]}];
  for(const {name,rect:[u,v,w,h]} of islands) {
    for(let y=Math.floor(v)-2;y<=Math.ceil(v+h)+1;y++)for(let x=Math.floor(u)-2;x<=Math.ceil(u+w)+1;x++) {
      const px=Math.max(0,Math.min(w,x-u)),py=Math.max(0,Math.min(h,y-v));
      const broad=Math.cos(px/24*Math.PI*2)*Math.sin(py*(32/24)*.19)*3;
      const coarse=Math.sin(Math.floor(px*(32/24)/3)*1.7+Math.floor(py*(32/24)/3)*2.1)*2;
      const wear=name==='caps'?0:Math.max(0,(py/h-.85)*12);
      const shade=broad+coarse-wear;
      ctx.fillStyle=`rgb(${[182+shade,159+shade,126+shade].map(Math.round).join(',')})`;ctx.fillRect(x,y,1,1);
    }
  }
  const texture=new Texture({name:'beige_stucco_wall_full_albedo.png',width:64,height:128,uv_width:64,uv_height:128}).fromDataURL(canvas.toDataURL()).add(false);textures.push(texture);
  const mesh=new Mesh({name:'BeigeStuccoWallFull',vertices:{},faces:{},origin:[0,0,0]}).init();elements.push(mesh);
  const manifest=[];let index=0;
  function quad(name,points,island) {
    const keys=points.map(p=>{const k='v'+index++;mesh.vertices[k]=p.map(v=>v*16);return k;});
    const [u,v,w,h]=islands[island].rect;
    const uv=island===2?[[u,v],[u,v+h],[u+w,v+h],[u+w,v]]:[[u,v+h],[u+w,v+h],[u+w,v],[u,v]];
    mesh.addFaces(new MeshFace(mesh,{vertices:keys,uv:Object.fromEntries(keys.map((k,i)=>[k,uv[i]])),texture:texture.uuid}));
    manifest.push({name,island:islands[island].name,points_m:points,uv_pixels:uv});
  }
  quad('front',[[-.5,0,.1],[.5,0,.1],[.5,5,.1],[-.5,5,.1]],0);
  quad('back',[[.5,0,-.1],[-.5,0,-.1],[-.5,5,-.1],[.5,5,-.1]],0);
  quad('right',[[.5,0,.1],[.5,0,-.1],[.5,5,-.1],[.5,5,.1]],1);
  quad('left',[[-.5,0,-.1],[-.5,0,.1],[-.5,5,.1],[-.5,5,-.1]],1);
  quad('top',[[-.5,5,.1],[.5,5,.1],[.5,5,-.1],[-.5,5,-.1]],2);
  quad('bottom',[[-.5,0,-.1],[.5,0,-.1],[.5,0,.1],[-.5,0,.1]],2);
  globalThis.stuccoManifest={texture:[64,128],texels_per_metre:24,islands,faces:manifest};
  mesh.select();Canvas.updateAll();Undo.finishEdit('Create full-height beige stucco wall');
  const guide=document.createElement('canvas');guide.width=64;guide.height=128;
  const g=guide.getContext('2d');g.fillStyle='#29262a';g.fillRect(0,0,64,128);
  for(const {rect:[u,v,w,h]} of islands){g.fillStyle='#b69f7e';g.fillRect(u,v,w,h);g.strokeStyle='#fff0db';g.strokeRect(u,v,w,h);}
  globalThis.stuccoGuide=guide.toDataURL();
  return {bounds_m:[1,5,.2],triangles:12,texture:[64,128]};
})()
