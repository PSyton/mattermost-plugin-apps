package apps_test

import (
	"testing"

	"github.com/mattermost/mattermost-plugin-apps/apps"
)

func TestCopyType(t *testing.T) {
	http := apps.HTTP{RootURL: "test1"}
	plugin := apps.Plugin{PluginID: "test2"}

	src := apps.Deploy{
		HTTP:   &http,
		Plugin: &plugin,
	}

	var dest apps.Deploy

	dest.CopyType(src, apps.DeployHTTP)

	if dest.HTTP == nil {
		t.Fatal("CopyType failed: HTTP is nil after copy")
	}

	if dest.HTTP.RootURL != "test1" {
		t.Fatalf("CopyType failed: expected RootURL='test1', got '%s'", dest.HTTP.RootURL)
	}

	dest.CopyType(src, apps.DeployPlugin)

	if dest.Plugin == nil {
		t.Fatal("CopyType failed: Plugin is nil after copy")
	}

	if dest.Plugin.PluginID != "test2" {
		t.Fatalf("CopyType failed: expected PluginID='test2', got '%s'", dest.Plugin.PluginID)
	}

	t.Log("SUCCESS: CopyType works correctly!")
}
