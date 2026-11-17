# Home Assistant automations and the helpers they use, managed declaratively.
# Imported from services/hass/default.nix.
#
# Everything here is read-only in the HA UI (traces still work). Edit it here
# and redeploy. `initial_state = true` makes sure every automation comes up
# enabled after a restart / redeploy.
{ ... }:

let
  # Window open (30 s) -> heating off; window closed -> previous mode restored.
  # The previous hvac mode is kept in an input_text helper so it survives
  # restarts. If the heating was already off when the window opened, the
  # helper stays empty and nothing is turned back on.
  windowHeating =
    {
      id,
      alias,
      window,
      thermostat,
      helper,
    }:
    {
      inherit id alias;
      description = "Heating off while the window is open, previous mode restored when it closes. Previous mode is stored in ${helper}.";
      mode = "queued";
      initial_state = true;
      triggers = [
        {
          trigger = "state";
          entity_id = window;
          to = "on";
          for.seconds = 30;
          id = "window_open";
        }
        {
          trigger = "state";
          entity_id = window;
          to = "off";
          id = "window_closed";
        }
        {
          trigger = "homeassistant";
          event = "start";
          id = "window_closed";
        }
      ];
      actions = [
        {
          choose = [
            # Window opened: remember the mode and switch off (only if heating was on)
            {
              conditions = [
                {
                  condition = "trigger";
                  id = "window_open";
                }
                {
                  condition = "template";
                  value_template = "{{ states('${thermostat}') not in ['off', 'unavailable', 'unknown'] }}";
                }
              ];
              sequence = [
                {
                  action = "input_text.set_value";
                  target.entity_id = helper;
                  data.value = "{{ states('${thermostat}') }}";
                }
                {
                  action = "climate.set_hvac_mode";
                  target.entity_id = thermostat;
                  data.hvac_mode = "off";
                }
              ];
            }
            # Window closed (or HA started with it closed): restore the saved mode, if any
            {
              conditions = [
                {
                  condition = "trigger";
                  id = "window_closed";
                }
                {
                  condition = "state";
                  entity_id = window;
                  state = "off";
                }
                {
                  condition = "template";
                  value_template = "{{ states('${helper}') not in ['', 'unknown', 'unavailable'] }}";
                }
              ];
              sequence = [
                {
                  action = "climate.set_hvac_mode";
                  target.entity_id = thermostat;
                  data.hvac_mode = "{{ states('${helper}') }}";
                }
                {
                  action = "input_text.set_value";
                  target.entity_id = helper;
                  data.value = "";
                }
              ];
            }
          ];
        }
      ];
    };

  bedroomWindow = "binary_sensor.bedroom_myggbett_door_window_sensor_door";
  bedroomLight = "light.kajplats_e27_cws_globe_1055lm";
in
{
  services.home-assistant.config = {
    # State helpers for the window automations. No `initial`, so HA restores
    # their last value after a restart.
    input_text = {
      bathroom_heating_previous_mode.name = "Bathroom heating previous mode";
      bedroom_heating_previous_mode.name = "Bedroom heating previous mode";
    };
    input_boolean = {
      bedroom_light_was_on.name = "Bedroom light was on";
    };

    "automation manual" = [
      (windowHeating {
        id = "bathroom_window_heating";
        alias = "Bathroom Window Heating";
        window = "binary_sensor.bathroom_myggbett_door_window_sensor_door";
        thermostat = "climate.radiator_thermostat_w600_2";
        helper = "input_text.bathroom_heating_previous_mode";
      })

      (windowHeating {
        id = "bedroom_window_heating";
        alias = "Bedroom Window Heating";
        window = bedroomWindow;
        thermostat = "climate.bedroom_bedroom";
        helper = "input_text.bedroom_heating_previous_mode";
      })

      # Window open -> light off (if it was on); window closed -> fade back on over 10 s.
      {
        id = "bedroom_window_light";
        alias = "Bedroom Window Light";
        description = "Light off while the window is open (only if it was on), fades back on over 10 s when it closes. Stored in input_boolean.bedroom_light_was_on.";
        mode = "queued";
        initial_state = true;
        triggers = [
          {
            trigger = "state";
            entity_id = bedroomWindow;
            to = "on";
            id = "window_open";
          }
          {
            trigger = "state";
            entity_id = bedroomWindow;
            to = "off";
            id = "window_closed";
          }
          {
            trigger = "homeassistant";
            event = "start";
            id = "window_closed";
          }
        ];
        actions = [
          {
            choose = [
              {
                conditions = [
                  {
                    condition = "trigger";
                    id = "window_open";
                  }
                  {
                    condition = "state";
                    entity_id = bedroomLight;
                    state = "on";
                  }
                ];
                sequence = [
                  {
                    action = "input_boolean.turn_on";
                    target.entity_id = "input_boolean.bedroom_light_was_on";
                  }
                  {
                    action = "light.turn_off";
                    target.entity_id = bedroomLight;
                  }
                ];
              }
              {
                conditions = [
                  {
                    condition = "trigger";
                    id = "window_closed";
                  }
                  {
                    condition = "state";
                    entity_id = bedroomWindow;
                    state = "off";
                  }
                  {
                    condition = "state";
                    entity_id = "input_boolean.bedroom_light_was_on";
                    state = "on";
                  }
                ];
                sequence = [
                  {
                    action = "light.turn_on";
                    target.entity_id = bedroomLight;
                    data.transition = 10;
                  }
                  {
                    action = "input_boolean.turn_off";
                    target.entity_id = "input_boolean.bedroom_light_was_on";
                  }
                ];
              }
            ];
          }
        ];
      }

      # BILRESA button 1 toggles the bedroom light.
      {
        id = "sleep_room_licht";
        alias = "sleep room licht";
        description = "BILRESA button 1 toggles the bedroom light.";
        mode = "single";
        initial_state = true;
        triggers = [
          {
            trigger = "state";
            entity_id = "event.bilresa_dual_button_button_1";
            # Ignore the button dropping off / coming back (e.g. Matter server
            # restart), which would otherwise toggle the light.
            not_from = [
              "unavailable"
              "unknown"
            ];
            not_to = [
              "unavailable"
              "unknown"
            ];
          }
        ];
        actions = [
          {
            action = "light.toggle";
            target.entity_id = bedroomLight;
          }
        ];
      }

      # Washing machine start/end notifications with energy cost.
      # Needs the blueprint file at
      # /var/lib/hass/blueprints/automation/Blackshome/appliance-notifications.yaml
      # and the input_number helpers below (both already exist from the UI).
      {
        id = "washing_machine_notify";
        alias = "washing_machine_notify";
        description = "used for washing machine cycles";
        initial_state = true;
        use_blueprint = {
          path = "Blackshome/appliance-notifications.yaml";
          input = {
            cost_per_kwh = "input_number.euro_kwh";
            end_message_cost = "Approx Cost €";
            end_notify_device = [ "edc521e9a69414c0564c3d0bc70dbc42" ];
            end_notify_interruption_level = "critical";
            end_notify_tag = "washing-clothes";
            end_power_consumption = "input_number.kwh_end_washing";
            end_repeat_count = 2;
            end_time_delay = 4;
            include_end_notify = "enable_end_notify_options";
            include_power_tracking = "enable_power_tracking_and_cost";
            include_start_notify = "enable_start_notify_options";
            power_consumption_sensor = "sensor.bathroom_waschmaschine_energy";
            power_sensor = "sensor.bathroom_waschmaschine_power";
            running_dead_zone = 10;
            start_notify_device = [ "edc521e9a69414c0564c3d0bc70dbc42" ];
            start_notify_tag = "washing-clothes";
            start_power_consumption = "input_number.kwh_start_washing";
            start_time_delay = 0.1;
          };
        };
      }
    ];
  };
}