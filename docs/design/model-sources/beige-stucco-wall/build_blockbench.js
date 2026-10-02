// Run in a new empty Generic Model project. One quarter of a 5 m wall.
(() => {
  if(Format.id!=='free'||Outliner.elements.length)throw new Error('Use an empty Generic Model project');
  const elements=[],textures=[];
  Undo.initEdit({elements,textures,outliner:true});
  Project.texture_width=64;Project.texture_height=64;
  const canvas=document.createElement('canvas');canvas.width=64;canvas.height=64;
  const ctx=canvas.getContext('2d');ctx.fillStyle='#b69f7e';ctx.fillRect(0,0,64,64);
  const islands=[{name:'front_back',rect:[2,2,32,40]},{name:'ends',rect:[40,2,6.4,40]},{name:'caps',rect:[2,48,32,6.4]}];
  for(const {name,rect:[u,v,w,h]} of islands) {
    for(let y=Math.floor(v)-2;y<=Math.ceil(v+h)+1;y++)for(let x=Math.floor(u)-2;x<=Math.ceil(u+w)+1;x++) {
      const px=Math.max(0,Math.min(w,x-u)),py=Math.max(0,Math.min(h,y-v));
      const broad=Math.cos(px/w*Math.PI*2)*Math.sin(py*.19)*3;
      const coarse=Math.sin(Math.floor(px/3)*1.7+Math.floor(py/3)*2.1)*2;
      const wear=name==='caps'?0:Math.max(0,(py/h-.85)*12);
      const shade=broad+coarse-wear;
      ctx.fillStyle=`rgb(${[182+shade,159+shade,126+shade].map(Math.round).join(',')})`;ctx.fillRect(x,y,1,1);
    }
  }
  const texture=new Texture({name:'beige_stucco_wall_albedo.png',width:64,height:64,uv_width:64,uv_height:64}).fromDataURL(canvas.toDataURL()).add(false);textures.push(texture);
  const mesh=new Mesh({name:'BeigeStuccoWall',vertices:{},faces:{},origin:[0,0,0]}).init();elements.push(mesh);
  const manifest=[];let index=0;
  function quad(name,points,island) {
    const keys=points.map(p=>{const k='v'+index++;mesh.vertices[k]=p.map(v=>v*16);return k;});
    const [u,v,w,h]=islands[island].rect;
    const uv=island===2?[[u,v],[u+w,v],[u+w,v+h],[u,v+h]]:[[u,v+h],[u+w,v+h],[u+w,v],[u,v]];
    mesh.addFaces(new MeshFace(mesh,{vertices:keys,uv:Object.fromEntries(keys.map((k,i)=>[k,uv[i]])),texture:texture.uuid}));
    manifest.push({name,island:islands[island].name,points_m:points,uv_pixels:uv});
  }
  quad('front',[[-.5,0,.1],[.5,0,.1],[.5,1.25,.1],[-.5,1.25,.1]],0);
  quad('back',[[.5,0,-.1],[-.5,0,-.1],[-.5,1.25,-.1],[.5,1.25,-.1]],0);
  quad('right',[[.5,0,.1],[.5,0,-.1],[.5,1.25,-.1],[.5,1.25,.1]],1);
  quad('left',[[-.5,0,-.1],[-.5,0,.1],[-.5,1.25,.1],[-.5,1.25,-.1]],1);
  quad('top',[[-.5,1.25,.1],[.5,1.25,.1],[.5,1.25,-.1],[-.5,1.25,-.1]],2);
  quad('bottom',[[-.5,0,-.1],[.5,0,-.1],[.5,0,.1],[-.5,0,.1]],2);
  globalThis.stuccoManifest={texture:[64,64],texels_per_metre:32,islands,faces:manifest};
  mesh.select();Canvas.updateAll();Undo.finishEdit('Create quarter-height beige stucco wall');
  return {bounds_m:[1,1.25,.2],triangles:12,texture:[64,64]};
})()
