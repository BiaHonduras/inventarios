import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';

const origin = 'https://biahonduras.github.io';
const cors = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin' };
const respond = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const recent = new Map();
const instructions = `Eres un asistente de ayuda para la aplicación de Control de Inventarios de BIA Honduras. Responde en español claro y breve. Da instrucciones sin inventar datos, permisos, botones ni resultados. Si no sabes algo dilo y sugiere consultarlo con un administrador. No ejecutes acciones ni solicites contraseñas, datos personales o claves. La aplicación tiene Resumen, Vencimientos, Inventarios Diarios, Ver Inventario, Justificaciones, Exportación Informe, Importar Inventarios, Importar Códigos y Depuración. La gestión de usuarios se realiza en la Intranet. Los permisos y sedes dependen de la cuenta. El inventario diario incluye sede, bodega, fecha, código, cajas/fardos y unidades. DIF compara lo contado con reportería. La importación usa formatos descargables; hay que revisar la vista previa. Para datos concretos o cifras actuales, indica que debes consultar la pantalla correspondiente; no tienes acceso a registros reales.`;

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return respond({ error: 'Método no permitido' }, 405);
  if (request.headers.get('origin') && request.headers.get('origin') !== origin) return respond({ error: 'Origen no permitido' }, 403);
  const token = request.headers.get('Authorization') || '';
  if (!/^Bearer\s+\S+$/i.test(token)) return respond({ error: 'Inicia sesión nuevamente' }, 401);
  try {
    const client = createClient(Deno.env.get('SUPABASE_URL') || '', Deno.env.get('SUPABASE_ANON_KEY') || '', { global: { headers: { Authorization: token } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: auth, error: authError } = await client.auth.getUser(token.replace(/^Bearer\s+/i, ''));
    if (authError || !auth.user) return respond({ error: 'Inicia sesión nuevamente' }, 401);
    const { data: profile, error: profileError } = await client.rpc('bia_profile');
    if (profileError || !profile?.is_active || !Array.isArray(profile.applications) || !profile.applications.includes('inventarios')) return respond({ error: 'No tienes acceso a Inventarios' }, 403);
    const payload = await request.json().catch(() => null);
    const question = typeof payload?.question === 'string' ? payload.question.trim() : '';
    if (!question || question.length > 800) return respond({ error: 'Escribe una pregunta de hasta 800 caracteres' }, 400);
    const key = Deno.env.get('OPENAI_API_KEY');
    if (!key) return respond({ error: 'El asistente con IA aún no está configurado' }, 503);
    const now = Date.now();
    for (const [id, entry] of recent) if (now - entry.start > 60000) recent.delete(id);
    const entry = recent.get(auth.user.id) || { start: now, count: 0 };
    if (entry.count >= 5) return respond({ error: 'Espera un minuto antes de volver a consultar' }, 429);
    entry.count++; recent.set(auth.user.id, entry);
    const upstream = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST', signal: AbortSignal.timeout(25000),
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: Deno.env.get('OPENAI_MODEL') || 'gpt-5-mini', instructions, input: question, max_output_tokens: 800, store: false })
    });
    if (!upstream.ok) {
      const payload = await upstream.json().catch(() => null);
      const code = String(payload?.error?.code || payload?.error?.type || '');
      const quotaCodes = ['insufficient_quota','credit_balance_exhausted','organization_spend_limit_exceeded','project_spend_limit_exceeded','organization_usage_limit_exceeded'];
      const category = quotaCodes.includes(code) ? 'quota' : upstream.status === 429 ? 'rate_limit' : upstream.status === 401 ? 'credentials' : 'upstream';
      console.error('OpenAI request failed', upstream.status, category);
      return respond({ error: 'El asistente con IA no está disponible', reason: category }, 502);
    }
    const result = await upstream.json();
    const answer = (result.output || []).flatMap(item => item.content || []).filter(part => part.type === 'output_text').map(part => part.text || '').join('\n').trim();
    if (!answer) return respond({ error: 'El servicio de IA no devolvió una respuesta' }, 502);
    return respond({ answer });
  } catch (error) { console.error('assistant unavailable', error instanceof Error ? error.name : 'error'); return respond({ error: 'El asistente no está disponible' }, 503); }
});

