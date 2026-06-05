#!/bin/sh
# ============================================================
#  theme_dark.sh — Custom ThemeSpec para openNDS
#  Dark theme inspirado en el splash page original de v1
#  CPD-safe: sin JS, sin CSS externo, todo inline
# ============================================================

title="theme_dark"

# --- Session quotas (0 = use global config) ---
sessiontimeout="0"
upload_rate="0"
download_rate="0"
upload_quota="0"
download_quota="0"
quotas="$sessiontimeout $upload_rate $download_rate $upload_quota $download_quota"

# --- Custom params/images/files (none needed) ---
ndscustomparams=""
ndscustomimages=""
ndscustomfiles=""
ndsparamlist="$ndsparamlist $ndscustomparams $ndscustomimages $ndscustomfiles"

# --- Additional FAS variables ---
additionalthemevars="tos terms"
fasvarlist="$fasvarlist $additionalthemevars"

userinfo="$title"

# ============================================================
#  Functions
# ============================================================

generate_splash_sequence() {
	click_to_continue
}

header() {
	gatewayurl=$(printf "${gatewayurl//%/\\x}")
	cat << HEADER_EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$gatewayname</title>
</head>
<body style="margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;background:#09090b;color:#fafafa;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1rem;background-image:radial-gradient(ellipse 80% 60% at 50% 0%,rgba(255,255,255,0.03) 0%,transparent 60%);">
HEADER_EOF
}

footer() {
	cat << FOOTER_EOF
</body>
</html>
FOOTER_EOF
	exit 0
}

click_to_continue() {
	gatewayurl=$(printf "${gatewayurl//%/\\x}")

	if [ "$terms" = "yes" ]; then
		display_terms
	fi

	if [ "$tos" = "accepted" ]; then
		auth_log

		if [ "$ndsstatus" = "authenticated" ]; then
			auth_success
		else
			auth_fail
		fi

		read_terms
		footer
	fi

	login_form
	read_terms
	footer
}

login_form() {
	cat << FORM_EOF
<div style="background:#18181b;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:1.75rem;max-width:360px;width:100%;position:relative;overflow:hidden;">
  <div style="position:absolute;top:0;left:0;right:0;height:1px;background:linear-gradient(90deg,transparent,rgba(255,255,255,0.12),transparent);"></div>

  <div style="margin-bottom:1.25rem;">
    <div style="display:inline-flex;align-items:center;gap:6px;background:#27272a;border:1px solid rgba(255,255,255,0.1);border-radius:99px;padding:4px 10px 4px 7px;font-size:11px;font-weight:500;color:#a1a1aa;letter-spacing:0.02em;margin-bottom:1rem;">
      <span style="width:6px;height:6px;border-radius:50%;background:#22c55e;box-shadow:0 0 6px #22c55e88;"></span>
      Red de invitados
    </div>
    <h1 style="font-size:1.25rem;font-weight:600;letter-spacing:-0.02em;color:#fafafa;margin:0 0 4px 0;">$gatewayname</h1>
    <p style="font-size:0.8125rem;color:#a1a1aa;line-height:1.5;margin:0;">Acceso gratuito con límite de tiempo. Acepta las condiciones para continuar.</p>
  </div>

  <div style="height:1px;background:rgba(255,255,255,0.08);margin:1.25rem 0;"></div>

  <div style="display:grid;gap:6px;margin-bottom:1.25rem;">
    <div style="display:flex;align-items:center;gap:10px;padding:9px 11px;background:#27272a;border:1px solid rgba(255,255,255,0.08);border-radius:8px;font-size:0.8125rem;color:#a1a1aa;">
      <span style="font-size:15px;">⏱</span>
      <span style="flex:1;">Sesión disponible</span>
      <span style="font-size:0.75rem;font-weight:500;color:#fafafa;">$sessiontimeout min</span>
    </div>
    <div style="display:flex;align-items:center;gap:10px;padding:9px 11px;background:#27272a;border:1px solid rgba(255,255,255,0.08);border-radius:8px;font-size:0.8125rem;color:#a1a1aa;">
      <span style="font-size:15px;">🚫</span>
      <span style="flex:1;">Contenido adulto</span>
      <span style="font-size:0.75rem;font-weight:500;color:#fafafa;">Bloqueado</span>
    </div>
    <div style="display:flex;align-items:center;gap:10px;padding:9px 11px;background:#27272a;border:1px solid rgba(255,255,255,0.08);border-radius:8px;font-size:0.8125rem;color:#a1a1aa;">
      <span style="font-size:15px;">📶</span>
      <span style="flex:1;">Velocidad máxima</span>
      <span style="font-size:0.75rem;font-weight:500;color:#fafafa;">$downloadrate kb/s</span>
    </div>
  </div>

  <form action="/opennds_preauth/" method="get">
    <input type="hidden" name="fas" value="$fas">
    <input type="hidden" name="tos" value="accepted">
    <input type="submit" value="Conectar a Internet" style="width:100%;padding:10px 16px;background:#f4f4f5;color:#18181b;border:none;border-radius:8px;font-family:inherit;font-size:0.875rem;font-weight:600;cursor:pointer;">
  </form>

  <div style="margin-top:1.25rem;">
    <div style="font-size:0.6875rem;font-weight:500;color:#52525b;letter-spacing:0.06em;text-transform:uppercase;margin-bottom:8px;display:flex;align-items:center;gap:8px;">
      <span style="flex:1;height:1px;background:rgba(255,255,255,0.08);"></span>
      Patrocinado por
      <span style="flex:1;height:1px;background:rgba(255,255,255,0.08);"></span>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
      <a href="https://crisego.com" target="_blank" rel="noopener" style="display:flex;flex-direction:column;gap:4px;padding:10px 12px;background:#27272a;border:1px solid rgba(255,255,255,0.08);border-radius:8px;text-decoration:none;cursor:pointer;">
        <span style="font-size:0.8125rem;font-weight:600;color:#fafafa;letter-spacing:-0.01em;">crisego.com</span>
        <span style="font-size:0.6875rem;color:#a1a1aa;line-height:1.4;">Soluciones y servicios tecnológicos</span>
      </a>
      <a href="https://termisearch.com" target="_blank" rel="noopener" style="display:flex;flex-direction:column;gap:4px;padding:10px 12px;background:#27272a;border:1px solid rgba(255,255,255,0.08);border-radius:8px;text-decoration:none;cursor:pointer;">
        <span style="font-size:0.8125rem;font-weight:600;color:#fafafa;letter-spacing:-0.01em;">termisearch.com</span>
        <span style="font-size:0.6875rem;color:#a1a1aa;line-height:1.4;">Búsqueda y gestión de términos</span>
      </a>
    </div>
  </div>

  <div style="margin-top:1rem;text-align:center;font-size:0.6875rem;color:#52525b;letter-spacing:0.02em;">
    Powered by OpenWrt · Al conectarte aceptas las condiciones de uso
  </div>
</div>
FORM_EOF
}

auth_success() {
	gatewayurl=$(printf "${gatewayurl//%/\\x}")
	cat << SUCCESS_EOF
<div style="background:#18181b;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:1.75rem;max-width:360px;width:100%;text-align:center;">
  <div style="font-size:2rem;margin-bottom:0.5rem;">✓</div>
  <h2 style="font-size:1.125rem;font-weight:600;color:#fafafa;margin:0 0 0.5rem 0;">Conectado</h2>
  <p style="font-size:0.8125rem;color:#a1a1aa;line-height:1.5;margin:0 0 1rem 0;">
    Tienes acceso a Internet.
  </p>
  <form>
    <input type="button" VALUE="Continuar" onClick="location.href='$originurl'" style="width:100%;padding:10px 16px;background:#f4f4f5;color:#18181b;border:none;border-radius:8px;font-family:inherit;font-size:0.875rem;font-weight:600;cursor:pointer;">
  </form>
</div>
SUCCESS_EOF
}

auth_fail() {
	gatewayurl=$(printf "${gatewayurl//%/\\x}")
	cat << FAIL_EOF
<div style="background:#18181b;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:1.75rem;max-width:360px;width:100%;text-align:center;">
  <div style="font-size:2rem;margin-bottom:0.5rem;color:#ef4444;">✗</div>
  <h2 style="font-size:1.125rem;font-weight:600;color:#fafafa;margin:0 0 0.5rem 0;">Error de conexión</h2>
  <p style="font-size:0.8125rem;color:#a1a1aa;line-height:1.5;margin:0 0 1rem 0;">
    Intenta de nuevo.
  </p>
  <form>
    <input type="button" VALUE="Reintentar" onClick="location.href='$originurl'" style="width:100%;padding:10px 16px;background:#f4f4f5;color:#18181b;border:none;border-radius:8px;font-family:inherit;font-size:0.875rem;font-weight:600;cursor:pointer;">
  </form>
</div>
FAIL_EOF
}

read_terms() {
	echo "
		<div style=\"margin-top:0.75rem;text-align:center;\">
			<form action=\"/opennds_preauth/\" method=\"get\">
				<input type=\"hidden\" name=\"fas\" value=\"$fas\">
				<input type=\"hidden\" name=\"terms\" value=\"yes\">
				<input type=\"submit\" value=\"Términos de Servicio\" style=\"padding:8px 16px;background:#27272a;color:#a1a1aa;border:1px solid rgba(255,255,255,0.08);border-radius:8px;font-family:inherit;font-size:0.75rem;cursor:pointer;\">
			</form>
		</div>
	"
}

display_terms() {
	cat << TERMS_EOF
<div style="background:#18181b;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:1.75rem;max-width:360px;width:100%;">
  <h2 style="font-size:1rem;font-weight:600;color:#fafafa;margin:0 0 1rem 0;">Términos de Servicio</h2>
  <div style="font-size:0.8125rem;color:#a1a1aa;line-height:1.6;">
    <p>Al usar esta red aceptas que se registren tu MAC y tiempo de sesión para control de acceso.</p>
    <p>El acceso es temporal y está sujeto a límites de tiempo. No uses la red para actividades ilegales.</p>
    <p>El contenido adulto está bloqueado. El administrador se reserva el derecho de revocar acceso.</p>
  </div>
  <form>
    <input type="button" VALUE="Volver" onClick="history.go(-1)" style="width:100%;padding:10px 16px;background:#27272a;color:#fafafa;border:1px solid rgba(255,255,255,0.08);border-radius:8px;font-family:inherit;font-size:0.875rem;font-weight:600;cursor:pointer;margin-top:1rem;">
  </form>
</div>
TERMS_EOF
	footer
}
