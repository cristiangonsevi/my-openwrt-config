package config

type Config struct {
	IP              string
	Modules         string
	DownSpeed       int
	UpSpeed         int
	SQMPercent      int
	WifiSSID24      string
	WifiSSID5G      string
	WifiPass        string
	GuestSSID       string
	GuestSpeedKbps  int
	GuestTimeoutMin int
}

func New() *Config {
	return &Config{
		DownSpeed:      150,
		UpSpeed:       20,
		SQMPercent:     90,
		WifiSSID24:     "CRISEGO",
		WifiSSID5G:     "CRISEGO-5G",
		WifiPass:       "123456789000",
		GuestSSID:      "CRISEGO-INVITADOS",
		GuestSpeedKbps: 5000,
		GuestTimeoutMin: 60,
	}
}

func (c *Config) SQM_DOWN() int {
	return c.DownSpeed * 1000 * c.SQMPercent / 100
}

func (c *Config) SQM_UP() int {
	return c.UpSpeed * 1000 * c.SQMPercent / 100
}