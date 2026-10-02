(() => {
  if(Format.id!=='free'||Outliner.elements.length)throw Error('Use an empty Generic Model project');
  const elements=[],textures=[];Undo.initEdit({elements,textures,outliner:true});
  Project.texture_width=64;Project.texture_height=64;
  const canvas=document.createElement('canvas');canvas.width=64;canvas.height=64;
  const ctx=canvas.getContext('2d');ctx.fillStyle='#50301b';ctx.fillRect(0,0,64,64);
  const islands=[{name:'risers',rect:[2,2,24,6]},{name:'treads',rect:[2,14,24,9.6]},{name:'sides_caps',rect:[2,32,48,30]}];
  for(const {name,rect:[u,v,w,h]} of islands)for(let y=v-2;y<Math.ceil(v+h)+2;y++)for(let x=u-2;x<Math.ceil(u+w)+2;x++){
    const px=Math.min(w,Math.max(0,x-u)),py=Math.min(h,Math.max(0,y-v));
    const grain=Math.sin(Math.floor(px/3)*2+Math.floor(py/5))*3;
    const color=name==='treads'?(py<1?[167,123,55]:[80,24,27]):[80,48,27];
    ctx.fillStyle=`rgb(${color.map(c=>Math.round(c+grain)).join(',')})`;ctx.fillRect(x,y,1,1);
  }
  const tex=new Texture({name:'casino_stairs_albedo.png',width:64,height:64,uv_width:64,uv_height:64}).fromDataURL(canvas.toDataURL()).add(false);textures.push(tex);
  const mesh=new Mesh({name:'CasinoStairFlight',vertices:{},faces:{},origin:[0,0,0]}).init();elements.push(mesh);
  const faces=[];let count=0;
  function quad(name,points,uv){const keys=points.map(p=>{const k='v'+count++;mesh.vertices[k]=p.map(v=>v*16);return k;});mesh.addFaces(new MeshFace(mesh,{vertices:keys,uv:Object.fromEntries(keys.map((k,i)=>[k,uv[i]])),texture:tex.uuid}));faces.push({name,points_m:points,uv_pixels:uv});}
  for(let i=0;i<5;i++){
    const z0=-.5+i*.4,z1=z0+.4,low=i*.25,high=low+.25;
    quad('riser_'+i,[[-.5,low,z0],[-.5,high,z0],[.5,high,z0],[.5,low,z0]],[[2,8],[2,2],[26,2],[26,8]]);
    quad('tread_'+i,[[-.5,high,z0],[-.5,high,z1],[.5,high,z1],[.5,high,z0]],[[2,14],[2,23.6],[26,23.6],[26,14]]);
    quad('left_'+i,[[-.5,0,z0],[-.5,0,z1],[-.5,high,z1],[-.5,high,z0]],[[2+i*9.6,62],[2+(i+1)*9.6,62],[2+(i+1)*9.6,62-high*24],[2+i*9.6,62-high*24]]);
    quad('right_'+i,[[.5,0,z1],[.5,0,z0],[.5,high,z0],[.5,high,z1]],[[2+(i+1)*9.6,62],[2+i*9.6,62],[2+i*9.6,62-high*24],[2+(i+1)*9.6,62-high*24]]);
  }
  quad('back',[[-.5,0,1.5],[.5,0,1.5],[.5,1.25,1.5],[-.5,1.25,1.5]],[[2,62],[26,62],[26,32],[2,32]]);
  quad('bottom',[[-.5,0,-.5],[.5,0,-.5],[.5,0,1.5],[-.5,0,1.5]],[[2,32],[2,56],[50,56],[50,32]]);
  globalThis.casinoStairManifest={dimensions_m:[1,1.25,2],texels_per_metre:24,texture:[64,64],islands,faces};
  globalThis.casinoStairCanvas=canvas;mesh.select();Canvas.updateAll();Undo.finishEdit('Create walnut carpet stair module');
  return {triangles:44,steps:5,run_m:2,rise_m:1.25};
})()
