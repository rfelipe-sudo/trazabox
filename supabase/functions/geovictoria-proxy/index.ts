import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const GV_BASE    = 'https://customerapi.geovictoria.com/api';
const GV_API_KEY = Deno.env.get('GV_API_KEY') ?? 'd3d0d1';
const GV_SECRET  = Deno.env.get('GV_SECRET')  ?? 'f57d7e8d';

async function hmacSha1(k:string,d:string):Promise<string>{const e=new TextEncoder();const ck=await crypto.subtle.importKey('raw',e.encode(k),{name:'HMAC',hash:'SHA-1'},false,['sign']);const s=await crypto.subtle.sign('HMAC',ck,e.encode(d));return btoa(String.fromCharCode(...new Uint8Array(s)));}
function pct(s:string){return encodeURIComponent(s).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());}
async function oAuth(method:string,url:string):Promise<string>{const ts=Math.floor(Date.now()/1000).toString(),n=crypto.randomUUID().replace(/-/g,'');const p:Record<string,string>={oauth_consumer_key:GV_API_KEY,oauth_nonce:n,oauth_signature_method:'HMAC-SHA1',oauth_timestamp:ts,oauth_version:'1.0'};const sorted=Object.keys(p).sort().map(k=>`${pct(k)}=${pct(p[k])}`).join('&');const sig=await hmacSha1(`${pct(GV_SECRET)}&`,`${method}&${pct(url)}&${pct(sorted)}`);p['oauth_signature']=sig;return 'OAuth '+Object.keys(p).sort().map(k=>`${k}="${pct(p[k])}"`).join(', ');}
async function gvRaw(path:string,body:unknown):Promise<{status:number,text:string}>{const url=`${GV_BASE}${path}`,auth=await oAuth('POST',url);const res=await fetch(url,{method:'POST',headers:{'Authorization':auth,'Content-Type':'application/json'},body:JSON.stringify(body)});return{status:res.status,text:await res.text()};}
async function gvPost(path:string,body:unknown):Promise<unknown>{const{status,text}=await gvRaw(path,body);if(status<200||status>=300)throw new Error(`GV ${path} HTTP ${status}: ${text.substring(0,300)}`);return JSON.parse(text);}

function sb(){return createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);}
function gvDate(d:string,s:boolean){return d.replace(/-/g,'')+(s?'000000':'235959');}
function parseHora(s?:string|null):string|null{
  if(!s||s==='00:00'||s==='00:00:00') return null;
  const m=s.match(/(\d{2}:\d{2})/);
  return m?m[1]+':00':null;
}

// Estructura real de GV permit/getpermissions:
// { ID_PERMISSION, ID_PERMISSION_TYPE, Identifier, Email,
//   PERMISSION_DESCRIPTION, CREATED_BY,
//   PERMISSION_END: "YYYYMMDDHHMMSS", PERMISSION_START: "YYYYMMDDHHMMSS",
//   PERMISSION_START_HOUR, PERMISSION_END_HOUR, PERMISSION_HOURS,
//   ID_PERMISSION_EXTERNAL }
type GVPerm={
  ID_PERMISSION?:string;
  ID_PERMISSION_TYPE?:string;
  Identifier:string;
  Email?:string;
  Name?:string;LastName?:string;
  PERMISSION_TYPE_NAME?:string;PermissionTypeName?:string;
  PERMISSION_DESCRIPTION?:string;
  CREATED_BY?:string;
  PERMISSION_START?:string;PERMISSION_END?:string;
  PERMISSION_START_HOUR?:string;PERMISSION_END_HOUR?:string;
  START_DATE?:string;END_DATE?:string;
  START_TIME?:string;END_TIME?:string;
};

function anyArray(raw:unknown):unknown[]{
  if(Array.isArray(raw))return raw;
  if(raw&&typeof raw==='object'){for(const v of Object.values(raw as object)){if(Array.isArray(v)&&(v as unknown[]).length>0)return v as unknown[];}}
  return [];
}
function gvPerms(raw:unknown):GVPerm[]{return anyArray(raw) as GVPerm[];}

function fgv(s?:string):string{
  if(!s)return new Date().toLocaleDateString('sv-SE');
  if(s.includes('-'))return s.substring(0,10);
  // formato YYYYMMDDHHMMSS
  return `${s.substring(0,4)}-${s.substring(4,6)}-${s.substring(6,8)}`;
}

function mapPerm(p:GVPerm){
  // PERMISSION_DESCRIPTION es el campo libre que escribe el jefe → es el «tipo real»
  // CREATED_BY es quien aprobó el permiso
  const desc=(p.PERMISSION_DESCRIPTION??'').trim();
  const tipo=p.PERMISSION_TYPE_NAME??p.PermissionTypeName??'Permiso';
  // Normalizar CREATED_BY (viene con espacios extra)
  const createdBy=(p.CREATED_BY??'').trim().replace(/\s+/g,' ');

  // Horas — vienen como "HH:MM" en PERMISSION_START_HOUR
  const hi = parseHora(p.START_TIME??p.PERMISSION_START_HOUR);
  const hf = parseHora(p.END_TIME??p.PERMISSION_END_HOUR);

  return{
    identifier:    p.Identifier,
    nombre:        p.Name?`${p.Name} ${p.LastName??''}`.trim():(p.Email??p.Identifier),
    rut:           null,
    tipo_permiso:  tipo,
    descripcion_tipo: desc,  // el campo real con el motivo
    fecha_inicio:  fgv(p.START_DATE??p.PERMISSION_START),
    fecha_fin:     fgv(p.END_DATE??p.PERMISSION_END),
    hora_inicio:   hi,
    hora_fin:      hf,
    origen:        null,
    created_by:    createdBy||null,
    id_permission: p.ID_PERMISSION??null,
    actualizado_at:new Date().toISOString(),
  };
}

async function upsertPermisos(perms:GVPerm[], client:ReturnType<typeof sb>){
  if(!perms.length)return 0;
  // Actualizar gv_identifier usando email
  for(const p of perms){
    if(p.Email){
      await client.from('tecnicos_traza_zc')
        .update({gv_identifier:p.Identifier})
        .ilike('email',p.Email)
        .is('gv_identifier',null);
    }
  }
  const rows=perms.map(p=>mapPerm(p));
  // Upsert con todos los campos nuevos
  const{error}=await client.from('gv_permisos')
    .upsert(rows,{onConflict:'identifier,fecha_inicio,tipo_permiso'});
  if(error)throw new Error('upsert permisos: '+error.message);
  return rows.length;
}

async function syncPermisosMes(anio:number,mes:number){
  const ul=new Date(anio,mes,0).getDate();
  const from=gvDate(`${anio}-${String(mes).padStart(2,'0')}-01`,true);
  const to  =gvDate(`${anio}-${String(mes).padStart(2,'0')}-${String(ul).padStart(2,'0')}`,false);
  try{
    const raw=await gvPost('/permit/getpermissions',{from,to});
    const perms=gvPerms(raw);
    if(!perms.length)return{inserted:0,message:'Sin permisos GV para el mes'};
    const n=await upsertPermisos(perms,sb());
    return{inserted:n};
  }catch(e){return{inserted:0,error:(e as Error).message};}
}

async function syncPermisosDia(fecha:string){
  const fr=gvDate(fecha,true),to=gvDate(fecha,false);
  try{
    const raw=await gvPost('/permit/getpermissions',{from:fr,to});
    const perms=gvPerms(raw);
    if(!perms.length)return{inserted:0};
    const n=await upsertPermisos(perms,sb());
    return{inserted:n};
  }catch(e){return{inserted:0,message:(e as Error).message};}
}

async function getResumenMensual(anio:number,mes:number){
  const{data:tecnicos}=await sb().rpc('calcular_resumen_asistencia',{p_anio:anio,p_mes:mes});
  return{anio,mes,tecnicos:tecnicos??[],fuente:'rol_turno+gv_permisos+ausencias_tecnicos'};
}

async function syncMes(anio:number,mes:number){
  const r=await syncPermisosMes(anio,mes);
  return{permisos_sincronizados:r.inserted,mensaje:'Resumen calculado desde rol_turno+permisos GV+ausencias',...r};
}

async function getResumenDia(fecha:string){
  const{data:perm}=await sb().from('gv_permisos').select('*').lte('fecha_inicio',fecha).gte('fecha_fin',fecha);
  return{fecha,permisos_activos:perm??[],total_permisos:(perm??[]).length};
}

async function debug(fecha:string){
  const fr=gvDate(fecha,true),to=gvDate(fecha,false);
  const r1=await gvRaw('/permit/getpermissions',{from:fr,to});
  let pc=0,sample:unknown=null;
  try{const arr=gvPerms(JSON.parse(r1.text));pc=arr.length;sample=arr[0]??null;}catch(_){}
  const client=sb();
  const{count:rolCount}=await client.from('rol_turno').select('*',{count:'exact',head:true}).eq('anio',parseInt(fecha.substring(0,4))).eq('mes',parseInt(fecha.substring(5,7)));
  const{count:permCount}=await client.from('gv_permisos').select('*',{count:'exact',head:true});
  return{
    permisos_gv: `[${r1.status}] ${pc} permisos para ${fecha}`,
    primer_permiso_raw: JSON.stringify(sample).substring(0,400),
    rol_turno_mes: `${rolCount} filas en rol_turno para ${fecha.substring(0,7)}`,
    gv_permisos_total: `${permCount} permisos en BD`,
  };
}

// ─── AttendanceBook: marcas físicas de entrada/salida ────────────────────────
const GV_V1='https://customerapi.geovictoria.com/api/v1';
const GV_LOGIN_USER=Deno.env.get('GV_USER')?? '6cf5e9';
const GV_LOGIN_PASS=Deno.env.get('GV_PASS')?? '2bdf6706';

async function gvBearerToken():Promise<string>{
  const res=await fetch(`${GV_V1}/Login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({User:GV_LOGIN_USER,Password:GV_LOGIN_PASS})});
  if(!res.ok)throw new Error(`GV Login ${res.status}`);
  const d=await res.json() as{token?:string};
  if(!d.token)throw new Error('GV Login: sin token');
  return d.token;
}

function rutLimpio(rut:string):string{return rut.replace(/[.\-\s]/g,'');}

type GVPeriod2={Date?:string;Worked?:boolean;Absent?:boolean;Holiday?:boolean;Punches?:unknown[];TimeOffs?:{TimeOffTypeDescription?:string}[]};
type GVUser2={Identifier?:string;Name?:string;LastName?:string;Periods?:GVPeriod2[]};

function estadoDia(p:GVPeriod2):string{
  if(p.Holiday)return 'Feriado';
  const to=p.TimeOffs??[];
  if(to.length>0)return to[0].TimeOffTypeDescription??'Permiso';
  if(p.Worked)return 'Presente';
  if(p.Absent)return 'Ausente';
  return 'Sin datos';
}

async function getAsistenciaMes(anio:number,mes:number,ruts:string[]){
  const token=await gvBearerToken();
  const ul=new Date(anio,mes,0).getDate();
  const p2=(n:number)=>String(n).padStart(2,'0');
  const start=`${anio}${p2(mes)}01000000`;
  const end=`${anio}${p2(mes)}${p2(ul)}235959`;
  const userIds=ruts.map(rutLimpio).filter(Boolean).join(',');
  const res=await fetch(`${GV_V1}/AttendanceBook`,{
    method:'POST',
    headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json'},
    body:JSON.stringify({StartDate:start,EndDate:end,UserIds:userIds}),
  });
  if(!res.ok){const txt=await res.text();throw new Error(`AttendanceBook ${res.status}: ${txt.substring(0,200)}`);}
  const raw=await res.json() as unknown;
  const usuarios=anyArray(raw) as GVUser2[];
  const result:Record<string,{dias_con_marca:number;dias_sin_marca:number;dias_feriado:number;dias_permiso:number;detalle:{fecha:string;estado:string;con_marca:boolean}[]}>={};
  for(const u of usuarios){
    const rut=rutLimpio(u.Identifier??'');
    if(!rut)continue;
    const detalle:{fecha:string;estado:string;con_marca:boolean}[]=[];
    let con=0,sin=0,fer=0,perm=0;
    for(const p of(u.Periods??[])){
      const fecha=(p.Date??'').substring(0,10);
      if(!fecha)continue;
      const estado=estadoDia(p);
      const conMarca=p.Worked===true;
      if(conMarca)con++;else if(p.Absent)sin++;
      if(p.Holiday)fer++;
      if((p.TimeOffs??[]).length>0)perm++;
      detalle.push({fecha,estado,con_marca:conMarca});
    }
    result[rut]={dias_con_marca:con,dias_sin_marca:sin,dias_feriado:fer,dias_permiso:perm,detalle};
  }
  return{anio,mes,tecnicos:result};
}

Deno.serve(async(req:Request)=>{
  const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, GET, OPTIONS'};
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  try{
    const body=await req.json().catch(()=>({})) as{action?:string;fecha?:string;anio?:number;mes?:number;ruts?:string[]};
    const ac=body.action??'resumen';
    const hoy=new Date().toLocaleDateString('sv-SE');
    const fecha=body.fecha??hoy;
    const[ay,ms]=fecha.split('-');
    const anio=body.anio??parseInt(ay),mes=body.mes??parseInt(ms);
    let r;
    if     (ac==='debug')           r=await debug(fecha);
    else if(ac==='test')            r={ok:true,mensaje:'Edge Function v17 OK'};
    else if(ac==='sync_dia')        r=await syncPermisosDia(fecha);
    else if(ac==='sync_todo')       r=await syncPermisosDia(fecha);
    else if(ac==='sync_permisos')   r=await syncPermisosDia(fecha);
    else if(ac==='sync_mes')        r=await syncMes(anio,mes);
    else if(ac==='resumen_mensual') r=await getResumenMensual(anio,mes);
    else if(ac==='asistencia_mes')  r=await getAsistenciaMes(anio,mes,body.ruts??[]);
    else                            r=await getResumenDia(fecha);
    return new Response(JSON.stringify({ok:true,...r}),{headers:{...cors,'Content-Type':'application/json'}});
  }catch(e){
    return new Response(JSON.stringify({ok:false,error:(e as Error).message}),{status:500,headers:{...cors,'Content-Type':'application/json'}});
  }
});
