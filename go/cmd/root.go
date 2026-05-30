package main

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"openwrt-cli/internal/config"
	"openwrt-cli/internal/ssh"
	"openwrt-cli/internal/ui"
)

var (
	ip       string
	modules  string
	password string
	reboot   bool
	noVerify bool
	verbose  bool
)

var rootCmd = &cobra.Command{
	Use:   "openwrt-cli",
	Short: "CLI para configurar routers OpenWrt de forma remota",
	Long: `OpenWrt Config CLI — Configuración avanzada de routers OpenWrt via SSH.

  Soporta: DNS + SafeSearch + DoH, SQM CAKE, WiFi, Portal Cautivo,
  bloqueo de anuncios y optimizaciones del kernel.

  La contraseña se puede pasar con -p/--password o con la variable
  de entorno SSHPASS. Si no se proporciona, se pide de forma interactiva.`,
	SilenceUsage: true,
}

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Ejecuta todos los módulos de configuración en el router",
	Long: `Se conecta al router via SSH y ejecuta todos los módulos
de configuración de forma secuencial con feedback en tiempo real.

  Ejemplos:
    openwrt-cli deploy -i 192.168.1.1 -p secreto
    openwrt-cli deploy -i 192.168.1.1 -m dns,sqm,wifi
    SSHPASS=secreto openwrt-cli deploy -i 192.168.1.1`,
	RunE: runDeploy,
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Muestra el estado de los servicios en el router",
	Long:  `Consulta el estado de DNS, SQM, WiFi, DoH y otros servicios.`,
	RunE:  runStatus,
}

var verifyCmd = &cobra.Command{
	Use:   "verify",
	Short: "Verifica la configuración aplicada",
	Long:  `Ejecuta comprobaciones de DNS, SQM, MSS clamping y más.`,
	RunE:  runVerify,
}

func init() {
	rootCmd.PersistentFlags().StringVarP(&ip, "ip", "i", "192.168.1.1", "IP del router OpenWrt")
	rootCmd.PersistentFlags().StringVarP(&modules, "modulos", "m", "", "Módulos a ejecutar (separados por coma)")
	rootCmd.PersistentFlags().StringVarP(&password, "password", "p", "", "Contraseña root del router (o usa SSHPASS)")

	rootCmd.AddCommand(deployCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(verifyCmd)

	deployCmd.Flags().BoolVarP(&reboot, "reboot", "r", false, "Reiniciar el router al finalizar")
	deployCmd.Flags().BoolVarP(&noVerify, "no-verify", "n", false, "Omitir verificación final")
	deployCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Modo verbose (logs de depuración)")

	viper.SetEnvPrefix("OPENWRT")
	viper.AutomaticEnv()
}

func getPassword() string {
	if p := viper.GetString("password"); p != "" {
		return p
	}
	if p := os.Getenv("SSHPASS"); p != "" {
		return p
	}
	if password != "" {
		return password
	}
	return ssh.ReadPassword()
}

func runDeploy(cmd *cobra.Command, args []string) error {
	if verbose {
		log.SetOutput(os.Stderr)
		log.SetFlags(log.LstdFlags | log.Lshortfile)
	} else {
		log.SetOutput(nil)
	}

	pass := getPassword()
	if pass == "" {
		ui.PrintError("Se requiere contraseña. Usa -p o SSHPASS")
		return fmt.Errorf("contraseña requerida")
	}

	cfg := config.New()
	cfg.IP = ip

	ui.PrintHeader()

	sp := ui.NewSpinner("Conectando al router %s...", ip)
	sp.Start()

	client, err := ssh.Dial(ip, pass)
	if err != nil {
		sp.Stop()
		ui.PrintError("No se pudo conectar: %v", err)
		return err
	}
	if verbose {
		client.SetLogger(os.Stderr)
	}
	sp.Stop()
	ui.PrintOK("Conectado a %s", ip)

	mods := getModules(modules)
	if len(mods) == 0 {
		mods = []string{"cleanup", "packages", "dns", "adblock", "wifi", "doh", "sqm", "kernel", "verify"}
	}

	ui.PrintSection("Ejecutando módulos (%d total)", len(mods))

	for i, mod := range mods {
		stepLabel := fmt.Sprintf("[%d/%d] %s", i+1, len(mods), strings.ToUpper(mod))
		sp = ui.NewSpinner("Ejecutando %s...", stepLabel)
		sp.Start()

		script, ok := modulesScripts[mod]
		if !ok {
			sp.Stop()
			ui.PrintWarn("Módulo desconocido: %s", mod)
			continue
		}

		output, err := client.Exec(script)
		sp.Stop()

		ui.PrintModuleOutput(stepLabel, output)

		if err != nil {
			ui.PrintError("%s falló", stepLabel)
		} else {
			ui.PrintOK("%s completado", stepLabel)
		}
	}

	if reboot {
		ui.PrintSection("Reiniciando router...")
		if err := client.Reboot(); err != nil {
			ui.PrintWarn("No se pudo reiniciar: %v", err)
		} else {
			ui.PrintOK("Router reiniciándose (volverá en ~30s)")
		}
	}

	ui.PrintSummary(client)
	return nil
}

func runStatus(cmd *cobra.Command, args []string) error {
	pass := getPassword()
	if pass == "" {
		ui.PrintError("Se requiere contraseña")
		return fmt.Errorf("contraseña requerida")
	}

	client, err := ssh.Dial(ip, pass)
	if err != nil {
		ui.PrintError("No se pudo conectar: %v", err)
		return err
	}
	defer client.Close()

	ui.PrintHeader()
	ui.PrintSection("Estado del sistema en %s", ip)

	checks := map[string]string{
		"DNS primario":    "uci -q get dhcp.@dnsmasq[0].server | tr ' ' '\\n' | head -1",
		"SQM CAKE":        "tc -s qdisc show | grep -q cake && echo 'Activo' || echo 'Inactivo'",
		"DoH proxy":       "netstat -tlnp 2>/dev/null | grep -qE '5053|5054' && echo 'Activo' || echo 'Inactivo'",
		"Portal cautivo":  "pgrep nodogsplash >/dev/null && echo 'Activo' || echo 'Inactivo'",
		"WiFi radios":     "uci show wireless | grep -c '=wifi-device' || echo 0",
		"WiFi interfaces": "uci show wireless | grep -c '=wifi-iface' || echo 0",
		"Uptime":          "uptime | sed 's/.*up /Up /;s/,.*load.*//'",
		"Memoria libre":   "free -h | awk '/Mem:/{print $7}'",
		"Fecha":           "date '+%Y-%m-%d %H:%M:%S'",
	}

	ui.PrintStatus(client, checks)
	return nil
}

func runVerify(cmd *cobra.Command, args []string) error {
	pass := getPassword()
	if pass == "" {
		ui.PrintError("Se requiere contraseña")
		return fmt.Errorf("contraseña requerida")
	}

	client, err := ssh.Dial(ip, pass)
	if err != nil {
		ui.PrintError("No se pudo conectar: %v", err)
		return err
	}
	defer client.Close()

	ui.PrintHeader()
	ui.PrintSection("Verificación en %s", ip)

	sp := ui.NewSpinner("Verificando...")
	sp.Start()

	checks := []struct {
		name string
		cmd  string
	}{
		{"NTP sincronizado", "ntpctl -s status 2>/dev/null | grep -qi 'synced' && echo OK || echo FALLO"},
		{"DNS resolución", "nslookup google.com 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FALLO"},
		{"SQM activo", "tc -s qdisc show | grep -q cake && echo OK || echo FALLO"},
		{"MSS clamping", "nft list chain inet fw4 forward 2>/dev/null | grep -q maxseg && echo OK || echo FALLO"},
		{"BBR habilitado", "sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep bbr && echo OK || echo FALLO"},
	}

	sp.Stop()

	for _, c := range checks {
		out, _ := client.Exec(c.cmd)
		result := strings.TrimSpace(out)
		if result == "OK" {
			ui.PrintOK("%s", c.name)
		} else {
			ui.PrintError("%s: %s", c.name, result)
		}
	}
	return nil
}

func getModules(m string) []string {
	if m == "" {
		return nil
	}
	mods := strings.Split(m, ",")
	result := make([]string, 0, len(mods))
	for _, mod := range mods {
		mod = strings.TrimSpace(strings.ToLower(mod))
		if mod != "" && moduleExists(mod) {
			result = append(result, mod)
		}
	}
	return result
}

func moduleExists(m string) bool {
	_, ok := modulesScripts[m]
	return ok
}