package ssh

import (
	"fmt"
	"os/exec"
	"strings"

	"golang.org/x/term"
)

type Client struct {
	IP       string
	Password string
}

func Dial(ip, password string) (*Client, error) {
	if password == "" {
		return nil, fmt.Errorf("se requiere contraseña (flag -p o variable SSHPASS)")
	}
	return &Client{IP: ip, Password: password}, nil
}

func (c *Client) Close() error {
	return nil
}

func (c *Client) Exec(cmd string) (string, error) {
	sshCmd := exec.Command("sshpass", "-p", c.Password, "ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "ConnectTimeout=10",
		"root@"+c.IP, cmd)

	output, err := sshCmd.CombinedOutput()
	return strings.TrimSpace(string(output)), err
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