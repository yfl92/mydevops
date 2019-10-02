package pkg

import (
	"io/ioutil"
	"strings"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"
	yaml "gopkg.in/yaml.v2"
)

type Deployment struct {
	Chiwen struct {
		Image   string   `yaml:"image"`
		Options []string `yaml:"options"`
	} `yaml:"chiwen"`
	Web struct {
		Image string `yaml:"image"`
	} `yaml:"web"`
	Master           *Host      `yaml:"master"`
	Hosts            []*Host    `yaml:"hosts"`
	Clusters         []*Cluster `yaml:"clusters"`
	InsecureRegistry []string   `yaml:"insecure_registry"`
}

func (d *Deployment) Create() error {
	var wg sync.WaitGroup
	hosts := d.ListHosts()
	wg.Add(len(hosts))

	for _, h := range hosts {
		go func(h *Host) {
			defer wg.Done()
			if !h.Exist() {
				if err := h.Create(); err != nil {
					panic(err)
				}
			}
		}(h)
	}
	wg.Wait()

	return nil
}

func (d *Deployment) Deploy() error {
	log.Debug("Deploying master...")
	if err := d.Master.Deploy(); err != nil {
		return err
	}

	// try to login, also works as a health-check to see if chiwen is ready
	myLogin(d.Master.ExternalIP, 5*time.Minute)
	defer myLogout()

	var wg sync.WaitGroup
	wg.Add(len(d.Hosts))
	log.Debug("Joining hosts...")
	for i := range d.Hosts {
		h := d.Hosts[i]
		go func() {
			defer wg.Done()
			if err := h.Join(); err != nil {
				panic(err)
			}
		}()
	}
	wg.Wait()

	log.Debug("Deploying clusters...")
	wg.Add(len(d.Clusters))
	for i := range d.Clusters {
		c := d.Clusters[i]
		go func() {
			defer wg.Done()
			c.Deploy()
		}()
	}
	wg.Wait()

	return nil
}

func (d *Deployment) Delete() {
	var wg sync.WaitGroup
	wg.Add(len(d.ListHosts()))

	for _, h := range d.ListHosts() {
		go func(h *Host) {
			defer wg.Done()
			if err := h.Delete(); err != nil {
				log.Debug(err.Error())
			}
		}(h)
	}

	wg.Wait()
}

func (d *Deployment) ListHosts() (hosts []*Host) {
	if d.Master != nil {
		hosts = append(hosts, d.Master)
	}
	hosts = append(hosts, d.Hosts...)
	return hosts
}

func (d *Deployment) masterIP() string {
	return d.Master.ExternalIP
}

func (d *Deployment) registry() string {
	img := strings.Split(d.Chiwen.Image, "/")
	return img[0]
}

func (d *Deployment) chiwenImage() string {
	return d.Chiwen.Image
}

func (d *Deployment) webImage() string {
	return d.Web.Image
}

func parseDeployment(data []byte) (*Deployment, error) {
	d := &Deployment{}
	if err := yaml.Unmarshal(data, d); err != nil {
		return nil, err
	}

	// set deployment
	if d.Master != nil {
		d.Master.deployment = d
	}

	for i := range d.Hosts {
		d.Hosts[i].deployment = d
	}
	for i := range d.Clusters {
		d.Clusters[i].deployment = d
		d.Clusters[i].Normalize()
	}

	return d, nil
}

func ParseDeployment(path string) (*Deployment, error) {
	content, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}

	return parseDeployment(content)
}