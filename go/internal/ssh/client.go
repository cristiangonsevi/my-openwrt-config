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
		fmt.Fprintf(c.Logger, "[DEBUG] Ejecutando comando en %s: %s\n", c.IP, cmd)
	}
	sshCmd := exec.Command("sshpass", "-p", c.Password, "ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "ConnectTimeout=10",
		"root@"+c.IP, cmd)

	output, err := sshCmd.CombinedOutput()
	if c.Logger != nil {
		fmt.Fprintf(c.Logger, "[DEBUG] Output: %s\n", string(output))
		if err != nil {
			fmt.Fprintf(c.Logger, "[ERROR] SSH exec error: %v\n", err)
		}
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