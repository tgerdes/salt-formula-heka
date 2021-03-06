-- Copyright 2015 Mirantis, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local table = require 'table'
local string = require 'string'
local cjson = require 'cjson'

local utils = require 'lma_utils'
local afd = require 'afd'

local afd_file = read_config('afd_file') or error('afd_file must be specified')
local afd_name = read_config('afd_name') or error('afd_name must be specified')
local hostname = read_config('hostname') or error('hostname must be specified')
local dimensions_json = read_config('dimensions') or ''
local activate_alerting = read_config('activate_alerting') or true
local enable_notification = read_config('enable_notification') or false
local notification_handler = read_config('notification_handler')

local all_alarms = require(afd_file)
local A = require 'afd_alarms'
A.load_alarms(all_alarms)

local ok, dimensions = pcall(cjson.decode, dimensions_json)
if not ok then
    error(string.format('dimensions JSON is invalid (%s)', dimensions_json))
end

function process_message()

    local metric_name = read_message('Fields[name]')
    local ts = read_message('Timestamp')

    local ok, value = utils.get_values_from_metric()
    if not ok then
        return -1, value
    end
    -- retrieve field values
    local fields = {}
    for _, field in ipairs (A.get_metric_fields(metric_name)) do
        local field_value = afd.get_entity_name(field)
        if not field_value then
            return -1, "Cannot find Fields[" .. field .. "] for the metric " .. metric_name
        end
        fields[field] = field_value
    end
    A.add_value(ts, metric_name, value, fields)
    return 0
end

function timer_event(ns)
    if A.is_started() then
        local state, alarms = A.evaluate(ns)
        if state then -- it was time to evaluate at least one alarm
            for _, alarm in ipairs(alarms) do
                afd.add_to_alarms(
                    alarm.state,
                    alarm.alert['function'],
                    alarm.alert.metric,
                    alarm.alert.fields,
                    {}, -- tags
                    alarm.alert.operator,
                    alarm.alert.value,
                    alarm.alert.threshold,
                    alarm.alert.window,
                    alarm.alert.periods,
                    alarm.alert.message)
            end

            afd.inject_afd_metric(state, hostname, afd_name, dimensions,
                activate_alerting, enable_notification, notification_handler)
        end
    else
        A.set_start_time(ns)
    end
end
