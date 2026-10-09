/* TACEDGE Mission Suite — shared runtime. Fully offline: no network calls except the
   optional local Field Docs portal (http://localhost:8090) on the same device. */
(function(){
  const qs = new URLSearchParams(location.search);
  const TE = window.TE = {};
  TE.mode = qs.get('mode') || window.MISSION_MODE || 'nominal';
  TE.tag = window.MISSION_TAG || qs.get('tag') || '';
  TE.unit = qs.get('unit') || window.MISSION_UNIT || 'TB-01';

  /* ---------- utils ---------- */
  TE.rng = function(seed){ let s = seed>>>0 || 1; return function(){ s ^= s<<13; s>>>=0; s ^= s>>17; s ^= s<<5; s>>>=0; return s/4294967296; }; };
  TE.clamp = (v,a,b)=>Math.max(a,Math.min(b,v));
  TE.lerp = (a,b,t)=>a+(b-a)*t;
  const MON=['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
  const p2=n=>String(n).padStart(2,'0');
  TE.dtg = function(d){ d=d||new Date(); return p2(d.getUTCDate())+p2(d.getUTCHours())+p2(d.getUTCMinutes())+'Z'+MON[d.getUTCMonth()]+String(d.getUTCFullYear()).slice(2); };
  TE.hms = function(d){ d=d||new Date(); return p2(d.getUTCHours())+':'+p2(d.getUTCMinutes())+':'+p2(d.getUTCSeconds())+'Z'; };

  /* ---------- geo: fictional AO inside the NTC training area ---------- */
  TE.AO = {lat0:35.30, lon0:-116.62};
  const MLAT=110540, MLON=111320*Math.cos(TE.AO.lat0*Math.PI/180);
  TE.toLL = (x,y)=>({lat:TE.AO.lat0 + y/MLAT, lon:TE.AO.lon0 + x/MLON});
  TE.mgrs = function(x,y,prec){
    const ll = TE.toLL(x,y); prec = prec||5;
    try{ const s = window.mgrs.forward([ll.lon,ll.lat],prec);
      const m = s.match(/^(\d{1,2}[A-Z])([A-Z]{2})(\d+)$/); if(!m) return s;
      const h=m[3].length/2; return m[1]+' '+m[2]+' '+m[3].slice(0,h)+' '+m[3].slice(h);
    }catch(e){ return '11S NV ----- -----'; }
  };

  /* ---------- procedural terrain (value-noise fbm) ---------- */
  TE.Terrain = function(seed){
    const R = TE.rng(seed||7), P = new Uint8Array(512), G = new Float32Array(256);
    for(let i=0;i<256;i++){ P[i]=i; G[i]=R(); }
    for(let i=255;i>0;i--){ const j=(R()*(i+1))|0; [P[i],P[j]]=[P[j],P[i]]; }
    for(let i=0;i<256;i++) P[i+256]=P[i];
    const sm=t=>t*t*(3-2*t);
    function vn(x,y){ const xi=Math.floor(x), yi=Math.floor(y), xf=x-xi, yf=y-yi, X=xi&255, Y=yi&255;
      const a=G[P[P[X]+Y]], b=G[P[P[X+1]+Y]], c=G[P[P[X]+Y+1]], d=G[P[P[X+1]+Y+1]], u=sm(xf), v=sm(yf);
      return a+(b-a)*u+(c-a)*v+(a-b-c+d)*u*v; }
    function h(x,y){ // x,y meters -> 0..1
      let f=1/9000, a=1, s=0, n=0; for(let o=0;o<6;o++){ s+=a*vn(x*f+31.7,y*f-12.3); n+=a; a*=.5; f*=2.03; }
      let v=s/n; v = Math.pow(TE.clamp((v-.22)/.62,0,1),1.35); // ridges & flat basins
      return v; }
    return {h, render(ctx,W,H,view,opt){
      opt=opt||{}; const sc=opt.scale||.5, w=Math.ceil(W*sc), hh=Math.ceil(H*sc);
      const img=ctx.createImageData(w,hh), d=img.data, mpp=view.mpp/sc;
      const pal=opt.palette||[[13,18,14],[24,30,22],[40,44,32],[58,58,42],[78,74,56]];
      const step=opt.contour||.055, hs=new Float32Array((w+1)*(hh+1));
      for(let j=0;j<=hh;j++) for(let i=0;i<=w;i++){ const x=view.cx+(i-w/2)*mpp, y=view.cy-(j-hh/2)*mpp; hs[j*(w+1)+i]=h(x,y); }
      for(let j=0;j<hh;j++) for(let i=0;i<w;i++){
        const k=j*(w+1)+i, v=hs[k], dx=hs[k+1]-v, dy=hs[k+w+1]-v;
        let shade=TE.clamp(.75+(-dx+dy)*mpp*.9,.35,1.25);
        const t=TE.clamp(v,0,.999)*(pal.length-1), pi=Math.floor(t), ft=t-pi, c0=pal[pi], c1=pal[Math.min(pi+1,pal.length-1)];
        let r=(c0[0]+(c1[0]-c0[0])*ft)*shade, g=(c0[1]+(c1[1]-c0[1])*ft)*shade, b=(c0[2]+(c1[2]-c0[2])*ft)*shade;
        if(Math.floor(v/step)!==Math.floor(hs[k+1]/step) || Math.floor(v/step)!==Math.floor(hs[k+w+1]/step)){
          const major = Math.floor(Math.max(v,hs[k+1])/step)%5===0; r+=major?34:16; g+=major?40:20; b+=major?26:12; }
        const o=(j*w+i)*4; d[o]=r; d[o+1]=g; d[o+2]=b; d[o+3]=255; }
      const oc=document.createElement('canvas'); oc.width=w; oc.height=hh; oc.getContext('2d').putImageData(img,0,0);
      ctx.save(); ctx.imageSmoothingEnabled=true; ctx.drawImage(oc,0,0,W,H); ctx.restore();
      if(opt.tint){ ctx.fillStyle=opt.tint; ctx.fillRect(0,0,W,H); }
    }};
  };

  /* ---------- logo (original mark) ---------- */
  TE.logo = '<svg viewBox="0 0 32 32"><path d="M16 2 29 9.5v13L16 30 3 22.5v-13z" fill="none" stroke="#4dff9a" stroke-width="1.6"/>'+
    '<path d="M9 19l7-8 7 8M12 22l4-4.5 4 4.5" fill="none" stroke="#4dff9a" stroke-width="1.8" stroke-linejoin="round"/></svg>';

  /* ---------- chrome ---------- */
  TE.init = function(cfg){
    TE.cfg = cfg;
    const deg = TE.mode==='degraded';
    const cls = 'UNCLASSIFIED // SIMULATED DATA — DEMONSTRATION ONLY';
    document.title = 'TACEDGE — '+cfg.title;
    document.body.innerHTML =
    '<div class="te-root">'+
      '<div class="te-class'+(deg?' deg':'')+'">'+cls+'</div>'+
      '<div class="te-head">'+
        '<div class="te-brand">'+TE.logo+'<div><b>TACEDGE</b><small>MISSION SUITE</small></div></div>'+
        '<div class="te-title"><h1>'+cfg.title+'</h1><span class="te-chip '+(deg?'bad':'ok')+'">'+cfg.version+'</span>'+
          (cfg.sub?'<span class="te-chip">'+cfg.sub+'</span>':'')+'</div>'+
        '<div class="te-stat">'+
          '<span><i class="te-dot" id="te-gpsd"></i>GPS <b id="te-gps">3D · 9 SV</b></span>'+
          '<span><i class="te-dot" id="te-netd"></i>NET <b id="te-net">MESH 5/5</b></span>'+
          '<span>BATT <b id="te-batt">87%</b></span>'+
          '<span class="te-clock" id="te-clk"></span>'+
          '<button class="te-btn" id="te-docsbtn" title="Offline field documentation">DOCS</button>'+
        '</div></div>'+
      '<div class="te-body" id="te-body"></div>'+
      '<div class="te-foot"><span>UNIT <b>'+(cfg.callsign||'BLACKHAWK 6')+'</b> · DEVICE '+TE.unit+' · AO <b>NTC / FT IRWIN (TRAINING)</b></span>'+
        '<span class="rh"><img class="rhl" src="../shared/brand/redhat-logo.svg" alt="Red Hat" onerror="this.remove()">Red Hat Enterprise Linux <i>●</i> image mode · bootc'+(TE.tag?' · IMAGE '+TE.tag:'')+'</span></div>'+
      '<div class="te-class'+(deg?' deg':'')+'">'+cls+'</div>'+
    '</div>'+
    '<div class="te-docs" id="te-docs"><header><span>FIELD DOCS — RED HAT OFFLINE KNOWLEDGE PORTAL (LOCAL)</span>'+
      '<button class="te-btn" id="te-docsx">CLOSE ✕</button></header><iframe id="te-docsf" title="Field docs"></iframe>'+
      '<div class="miss" id="te-docsm"><b>FIELD DOCS NOT DEPLOYED ON THIS DEVICE</b>Deploy “Offline Knowledge Portal” from the mission controller, then try again.</div></div>';
    const clk=document.getElementById('te-clk'), batt=document.getElementById('te-batt');
    let b=87; const tick=()=>{ clk.textContent=TE.dtg(); };
    tick(); setInterval(tick,1000); setInterval(()=>{ b=Math.max(41,b-1); batt.textContent=b+'%'; },90000);
    if(deg){ document.getElementById('te-netd').className='te-dot red'; document.getElementById('te-net').textContent='NO FEED';
      document.getElementById('te-gpsd').className='te-dot amb'; document.getElementById('te-gps').textContent='2D · 4 SV'; }
    // Field docs overlay
    const docs=document.getElementById('te-docs'), fr=document.getElementById('te-docsf'), miss=document.getElementById('te-docsm');
    document.getElementById('te-docsbtn').onclick=()=>{
      docs.classList.add('open'); fr.style.display='none'; miss.style.display='none';
      fetch('http://localhost:8090/',{mode:'no-cors',cache:'no-store'}).then(()=>{ fr.style.display='block'; if(!fr.src) fr.src='http://localhost:8090/'; })
        .catch(()=>{ miss.style.display='flex'; });
    };
    document.getElementById('te-docsx').onclick=()=>docs.classList.remove('open');
    return document.getElementById('te-body');
  };

  TE.setNet = function(text,level){ document.getElementById('te-net').textContent=text;
    document.getElementById('te-netd').className='te-dot'+(level==='amb'?' amb':level==='red'?' red':''); };

  TE.degradedBanner = function(host,title,sub){
    const d=document.createElement('div'); d.className='te-degr'; d.innerHTML='<span class="blink">⚠</span> '+title+'<small>'+sub+'</small>';
    host.appendChild(d); return d; };

  TE.log = function(el,msg,cls,max){
    const d=document.createElement('div'); d.innerHTML='<span class="t">'+TE.hms()+'</span><span class="'+(cls||'')+'">'+msg+'</span>';
    el.insertBefore(d,el.firstChild); while(el.children.length>(max||30)) el.removeChild(el.lastChild); };

  // milsymbol helper -> cached canvas
  const symCache={};
  TE.sym = function(sidc,size,opts){
    const key=sidc+size+JSON.stringify(opts||{}); if(symCache[key]) return symCache[key];
    const s=new window.ms.Symbol(sidc,Object.assign({size:size||22,frame:true,fill:true,monoColor:'',infoColor:'#cfe3d8',outlineWidth:2,outlineColor:'#000'},opts||{}));
    return symCache[key]={c:s.asCanvas(),a:s.getAnchor(),sz:s.getSize()};
  };
})();
