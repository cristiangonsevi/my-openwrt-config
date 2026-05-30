package ssh

import (
	"fmt"
	"io"
	"os/exec"
	"strings"

	"golang.org/x/term"
)

type Client struct {
	IP       string
	Password string
	Logger   io.Writer
}

func Dial(ip, password string) (*Client, error) {
	if password == "" {
		return nil, fmt.Errorf("se requiere contraseña (flag -p o variable SSHPASS)")
	}
	return &Client{IP: ip, Password: password, Logger: io.Discard}, nil
}

func (c *Client) Close() error {
	return nil
}

func (c *Client) Exec(cmd string) (string, error) {
	if c.Logger != nil {
		fmt.Fprintf(c.Logger, "[DEBUG] === Nuevo comando ===\n")
		fmt.Fprintf(c.Logger, "[DEBUG] IP: %s\n", c.IP)
		fmt.Fprintf(c.Logger, "[DEBUG] Cmd length: %d bytes\n", len(cmd))
		fmt.Fprintf(c.Logger, "[DEBUG] Cmd: %s\n", cmd)
	}

	sshArgs := []string{
		"-p", c.Password,
		"ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "ConnectTimeout=30",
		"-o", "ServerAliveInterval=30",
		"-o", "ServerAliveCountMax=3",
		"root@" + c.IP, cmd,
	}

	if c.Logger != nil {
		fmt.Fprintf(c.Logger, "[DEBUG] Full cmd: sshpass %v\n", sshArgs)
	}

	sshCmd := exec.Command("sshpass", sshArgs...)

	output, err := sshCmd.CombinedOutput()

	if c.Logger != nil {
		fmt.Fprintf(c.Logger, "[DEBUG] Exit code: %v\n", sshCmd.ProcessState.ExitCode())
		fmt.Fprintf(c.Logger, "[DEBUG] Output length: %d bytes\n", len(output))
		fmt.Fprintf(c.Logger, "[DEBUG] Output: %s\n", string(output))
		if err != nil {
			fmt.Fprintf(c.Logger, "[ERROR] SSH exec error: %v\n", err)
		}
		fmt.Fprintf(c.Logger, "[DEBUG] === Fin comando ===\n")
	}

	return strings.TrimSpace(string(output)), err
}

func (c *Client) SetLogger(w io.Writer) {
	c.Logger = w
}

func (c *Client) Reboot() error {
	_, err := c.Exec("reboot")
	return err
}

func ReadPassword() string {
	fmt.Print("Contraseña root: ")
	pass, _ := term.ReadPassword(int(0))
	fmt.Println()
	return string(pass)
}