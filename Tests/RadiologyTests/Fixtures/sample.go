// Package scan reads 放射線 studies.
package scan

import (
	"fmt"
	"strings"
)

const MaxScans = 10

var defaultTitle = "胸部"

type Modality int

type Renderer interface {
	Render() string
	Name() string
}

type Scan struct {
	Title string `json:"title"`
	Count int
}

func (s *Scan) Render() string {
	parts := []string{s.Title}
	for i := 0; i < s.Count; i++ {
		parts = append(parts, fmt.Sprintf("%d", i))
	}
	switch s.Count {
	case 0:
		return ""
	default:
		return strings.Join(parts, ",")
	}
}

func New(title string) *Scan {
	f := func(v string) string { return strings.TrimSpace(v) }
	return &Scan{Title: f(title), Count: len(title)}
}
