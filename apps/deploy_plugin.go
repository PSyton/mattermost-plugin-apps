// Copyright (c) 2020-present Mattermost, Inc. All Rights Reserved.
// See License for license information.

package apps

import (
	"github.com/mattermost/mattermost-plugin-apps/utils"
)

const PluginAppPath = "/app"

// Plugin contains metadata for an app that is implemented and is deployed
// and accessed as a local Plugin. The JSON name `plugin` must match the type.
type Plugin struct {
	PluginID string `json:"plugin_id,omitempty"`
}

func (p *Plugin) Validate() error {
	if p == nil {
		return nil
	}
	if p.PluginID == "" {
		return utils.NewInvalidError("plugin_id must be set for Plugin apps")
	}
	return nil
}
