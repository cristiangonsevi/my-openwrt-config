package ui

import (
	"fmt"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/charmbracelet/lipgloss"
)

var (
	brandStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FAFAFA")).
			Background(lipgloss.Color("#27272A")).
			Padding(0, 1)

	successStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#22C55E")).
			Bold(true)

	warnStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#EAB308")).
			Bold(true)

	errorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#EF4444")).
			Bold(true)

	infoStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#38BDF8")).
			Bold(true)

	sectionStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FAFAFA")).
			Bold(true).
			Underline(true)

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#71717A"))

	headerStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FAFAFA")).
			Background(lipgloss.Color("#18181B")).
			Width(60)

	borderStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#27272A"))
)

func PrintHeader() {
	fmt.Println()
	fmt.Println(brandStyle.Render("  openwrt-cli  "))
	fmt.Println()
}

func PrintSection(format string, args ...interface{}) {
	fmt.Println()
	fmt.Println(sectionStyle.Render(fmt.Sprintf("▶ %s", fmt.Sprintf(format, args...))))
	fmt.Println()
}

func PrintOK(format string, args ...interface{}) {
	fmt.Printf("  %s %s\n", successStyle.Render("✓"), fmt.Sprintf(format, args...))
}

func PrintWarn(format string, args ...interface{}) {
	fmt.Printf("  %s %s\n", warnStyle.Render("⚠"), fmt.Sprintf(format, args...))
}

func PrintError(format string, args ...interface{}) {
	fmt.Printf("  %s %s\n", errorStyle.Render("✗"), fmt.Sprintf(format, args...))
}

func PrintInfo(format string, args ...interface{}) {
	fmt.Printf("  %s %s\n", infoStyle.Render("ℹ"), fmt.Sprintf(format, args...))
}

func PrintModuleOutput(label, output string) {
	if output == "" {
		return
	}
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			fmt.Printf("    %s\n", dimStyle.Render(line))
		}
	}
}

type Spinner struct {
	mu       sync.Mutex
	message  string
	args     []interface{}
	stopCh   chan struct{}
	doneCh   chan struct{}
	running  bool
	ticker   *time.Ticker
}

func NewSpinner(format string, args ...interface{}) *Spinner {
	return &Spinner{
		message: format,
		args:    args,
		stopCh:  make(chan struct{}),
		doneCh:  make(chan struct{}),
	}
}

func (s *Spinner) Start() {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return
	}
	s.running = true
	s.stopCh = make(chan struct{})
	s.doneCh = make(chan struct{})
	s.ticker = time.NewTicker(80 * time.Millisecond)
	s.mu.Unlock()

	go s.run()
}

func (s *Spinner) run() {
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	i := 0

	fmt.Printf("\r  %s %s", infoStyle.Render(frames[i]), fmt.Sprintf(s.message, s.args...))

	for {
		select {
		case <-s.ticker.C:
			i = (i + 1) % len(frames)
			clearLine()
			fmt.Printf("\r  %s %s", infoStyle.Render(frames[i]), fmt.Sprintf(s.message, s.args...))
		case <-s.stopCh:
			clearLine()
			close(s.doneCh)
			return
		}
	}
}

func (s *Spinner) Stop() {
	s.mu.Lock()
	if !s.running {
		s.mu.Unlock()
		return
	}
	s.running = false
	s.mu.Unlock()

	close(s.stopCh)
	<-s.doneCh
	s.ticker.Stop()
	clearLine()
}

func clearLine() {
	fmt.Printf("\r%s\r", strings.Repeat(" ", terminalWidth()))
}

func terminalWidth() int {
	w, _, _ := size()
	if w == 0 {
		w = 80
	}
	return w
}

func size() (int, int, error) {
	return 80, 24, nil
}

type Check struct {
	Name  string
	Cmd   string
	Label string
}

func PrintStatus(client sshClient, checks map[string]string) {
	var wg sync.WaitGroup
	results := make(map[string]string)
	var mu sync.Mutex

	for name, cmd := range checks {
		wg.Add(1)
		go func(n, c string) {
			defer wg.Done()
			out, _ := client.Exec(c)
			mu.Lock()
			results[n] = strings.TrimSpace(out)
			mu.Unlock()
		}(name, cmd)
	}

	wg.Wait()

	for name, val := range results {
		label := fmt.Sprintf("%-20s", name)
		if strings.Contains(val, "Activo") || val == "OK" {
			fmt.Printf("  %s  %s\n", successStyle.Render("✓"), fmt.Sprintf("%s: %s", label, val))
		} else if strings.Contains(val, "Inactivo") || val == "FALLO" {
			fmt.Printf("  %s  %s\n", errorStyle.Render("✗"), fmt.Sprintf("%s: %s", label, val))
		} else {
			fmt.Printf("  %s  %s\n", infoStyle.Render("•"), fmt.Sprintf("%s: %s", label, val))
		}
	}
}

func PrintVerify(client sshClient, checks []Check) {
	for _, c := range checks {
		out, _ := client.Exec(c.Cmd)
		result := strings.TrimSpace(out)
		if result == "OK" {
			PrintOK("%s", c.Name)
		} else {
			PrintError("%s: %s", c.Name, result)
		}
	}
}

func PrintSummary(client sshClient) {
	PrintSection("Resumen")
	checks := map[string]string{
		"DNS":         "uci -q get dhcp.@dnsmasq[0].server | tr ' ' '\\n' | head -1",
		"SQM CAKE":    "tc -s qdisc show | grep -q cake && echo Activo || echo Inactivo",
		"DoH":         "netstat -tlnp 2>/dev/null | grep -qE '5053|5054' && echo Activo || echo Inactivo",
	}

	results := make(map[string]string)
	var mu sync.Mutex
	var wg sync.WaitGroup

	for name, cmd := range checks {
		wg.Add(1)
		go func(n, c string) {
			defer wg.Done()
			out, _ := client.Exec(c)
			mu.Lock()
			results[n] = strings.TrimSpace(out)
			mu.Unlock()
		}(name, cmd)
	}

	wg.Wait()

	for name, val := range results {
		fmt.Printf("  %-12s %s\n", name+":", dimStyle.Render(val))
	}

	fmt.Println()
	PrintInfo("Log guardado en: /tmp/openwrt_setup.log")
}

type sshClient interface {
	Exec(cmd string) (string, error)
}

func init() {
	if w, h, err := size(); err == nil && w > 0 && h > 0 {
		_ = h
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func padRight(s string, w int) string {
	if utf8.RuneCountInString(s) >= w {
		return s
	}
	return s + strings.Repeat(" ", w-utf8.RuneCountInString(s))
}