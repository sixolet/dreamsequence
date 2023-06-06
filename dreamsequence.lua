-- Dreamsequence v1.0.3
-- Dan Stroud @modularbeat
--
-- KEY 2: Play/pause
-- KEY 3: Reset
--
-- ENC 2: Select
-- ENC 3: Edit
--
-- Crow IN 1: CV in
-- Crow IN 2: Trigger in
-- Crow OUT 1: V/oct out
-- Crow OUT 2: Trigger/envelope out
-- Crow OUT 3: Clock out
-- Crow OUT 4: Event triggers


g = grid.connect()
include("dreamsequence/lib/includes")
local nb = include("lib/nb/lib/nb")
-- transport messages will be sent to whatever is configured in the global midi parameters

function init()
  -- To-do, add options for selecting MIDI in/out ports
  in_midi = midi.connect(1)

  nb:init()
  in_midi.event = function(data)
    local d = midi.to_msg(data)
    -- if params:get('clock_source') == 2 and d.type == 'stop' then -- placeholder for determining source of transport.stop
    if d.type == "note_on" then
      local note = params:get('chord_preload') == 0 and quantize_note(d.note - 35, 'midi') or
          pre_quantize_note(d.note - 35, 'midi')
      local player = params:lookup_param("voice_id"):get_player()
      player:play_note(note, 0.5, midi_duration / 96)
    end
  end
  init_generator()
  -- Turn off built-in Crow clock so it doesn't conflict with ours which only fires when transport is running.

  --GLOBAL PARAMS
  params:add_separator('Global')
  params:add_number("transpose", "Key", -12, 12, 0, function(param) return transpose_string(param:get()) end)
  params:add_number('mode', 'Mode', 1, 9, 1, function(param) return mode_index_to_name(param:get()) end)
  -- moving action to post-bang
  -- params:set_action('mode', function() update_chord_action() end)
  params:add_number('chord_preload', 'Chord preload', 0, 10, div_to_index('1/64'),
    function(param) return divisions_string(param:get()) end)
  params:set_action('chord_preload', function(x) chord_preload(x) end)
  -- Not used currently but might re-implement at some point
  -- params:add_number('count_in', 'Count-in', 0, 8, 0)
  -- params:add_number('clock_offset', 'Clock offset', -999, 999, 0)

  --ARRANGER PARAMS
  params:add_separator('Arranger')
  params:add_number('arranger_enabled', 'Enabled', 0, 1, 0, function(param) return t_f_string(param:get()) end)
  params:set_action('arranger_enabled', function()
    grid_redraw(); update_arranger_enabled()
  end)
  params:add_option('playback', 'Arranger', { 'Loop', 'One-shot' }, 1)
  params:set_action('playback', function()
    grid_redraw(); arranger_ending()
  end)


  -- EVENT PARAMS
  params:add_option('event_category', 'Category', { 'Global', 'Chord', 'Arp', 'MIDI harmonizer', 'CV harmonizer' }, 1)
  params:set_action('event_category', function() update_menus() end)
  params:hide(params.lookup['event_category'])
  event_display_names = {} -- to-do: make local after debug
  for i = 1, #events_lookup do
    event_display_names[i] = events_lookup[i].name
  end
  params:add_option('event_name', 'Event', event_display_names, 1) -- Default value will be overwritten later in Init
  params:set_action('event_name', function() update_menus() end)
  params:hide(params.lookup['event_name'])
  params:add_option('event_value_type', 'Type', { 'Set', 'Increment' }, 1)
  params:hide(params.lookup['event_value_type'])
  params:add_number('event_value', 'Value', -999, 999, 0)
  params:hide(params.lookup['event_value'])


  --CHORD PARAMS
  params:add_separator('Chord')
  nb:add_param("chord_voice", "Voice")
  params:add_option('chord_generator', 'C-gen', chord_algos['name'], 1)
  params:add_number('chord_div_index', 'Step length', 1, 57, 15, function(param) return divisions_string(param:get()) end)
  params:set_action('chord_div_index', function() set_div('chord') end)
  params:add_number('chord_duration_index', 'Duration', 1, 57, 15,
    function(param) return divisions_string(param:get()) end)
  params:set_action('chord_duration_index', function() set_duration('chord') end)
  params:add_number('chord_octave', 'Octave', 1, 7, 2)
  params:add_number('chord_type', 'Chord type', 3, 4, 3, function(param) return chord_type(param:get()) end)
  params:add_number('chord_inversion', 'Inversion', 0, 16, 0)
  params:add_number('chord_spread', 'Spread', 0, 6, 0)



  --ARP PARAMS
  params:add_separator('Arp')
  nb:add_param("arp_voice", "Voice")
  params:add_option('arp_generator', 'A-gen', arp_algos['name'], 1)
  params:add_number('arp_div_index', 'Step length', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('arp_div_index', function() set_div('arp') end)
  params:add_number('arp_duration_index', 'Duration', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('arp_duration_index', function() set_duration('arp') end)
  params:add_number('arp_octave', 'Octave', 1, 7, 2)
  params:add_number('arp_chord_type', 'Chord type', 3, 4, 3, function(param) return chord_type(param:get()) end)
  params:add_option("arp_mode", "Mode", { 'Loop', 'One-shot' }, 1)


  --MIDI PARAMS
  params:add_separator('MIDI')
  nb:add_param("midi_voice", "Voice")
  params:add_number('midi_duration_index', 'Duration', 1, 57, 10,
    function(param) return divisions_string(param:get()) end)
  params:set_action('midi_duration_index', function() set_duration('midi') end)
  params:add_number('midi_octave', 'Octave', 1, 7, 2)
  params:add_number('midi_chord_type', 'Chord type', 3, 4, 3, function(param) return chord_type(param:get()) end)


  --CV/CROW PARAMS
  params:add_separator('Crow')
  -- Crow clock uses hybrid notation/PPQN
  nb:add_param("crow_voice", "Voice")
  params:add_number('crow_duration_index', 'Duration', 1, 57, 10,
    function(param) return divisions_string(param:get()) end)
  params:set_action('crow_duration_index', function() set_duration('crow') end)
  params:add_number('crow_octave', 'Octave', 1, 7, 2)
  params:add_number('crow_chord_type', 'Chord type', 3, 4, 3, function(param) return chord_type(param:get()) end)

  params:add_separator('Voices')
  nb:add_player_params()
  glyphs = {
    --loop glyph
    { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 0, 1 }, { 0, 2 }, { 4, 2 }, { 4, 3 }, { 1, 4 }, { 2, 4 }, { 3, 4 } },
    --one-shot glyph
    { { 2, 0 }, { 3, 1 }, { 0, 2 }, { 1, 2 }, { 4, 2 }, { 3, 3 }, { 2, 4 } },
    -- pause
    { { 0, 0 }, { 1, 0 }, { 3, 0 }, { 4, 0 }, { 0, 1 }, { 1, 1 }, { 3, 1 }, { 4, 1 }, { 0, 2 }, { 1, 2 }, { 3, 2 },
      { 4, 2 }, { 0, 3 }, { 1, 3 }, { 3, 3 },
      { 4, 3 },
      { 0,
        4 }, { 1,
      4 }, { 3,
      4 }, { 4,
      4 } },
    -- play
    { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 }, { 0, 3 }, { 1, 3 },
      { 2, 3 }, { 0, 4 }, { 1, 4 } },
    -- reset/stopped
    { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 0, 2 },
      { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 },
      { 0, 3 },
      { 1,
        3 }, { 2,
      3 }, { 3,
      3 }, { 4,
      3 }, { 0,
      4 }, { 1,
      4 }, { 2,
      4 }, { 3,
      4 }, { 4,
      4 } }
  }

  clock_start_method = 'start'

  -- Send out MIDI stop on launch if clock ports are enabled
  transport_multi_stop()

  arranger_enabled = false
  chord_seq_retrig = true
  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  -- voltage threshold, hysteresis, "rising", "falling", or “both"
  -- TODO: might want to use as a gate with "both"
  crow.input[2].mode("change", 2, 0.1, "rising")
  crow.input[2].change = crow_trigger
  -- time,level,polarity
  crow.output[2].action = "pulse(.001,5,1)"
  crow.output[3].slew = 0
  screen_views = { 'Session', 'Events' }
  screen_view_index = 1
  screen_view_name = screen_views[screen_view_index]
  grid_dirty = true
  -- grid "views" are decoupled from screen "pages"
  grid_views = { 'Arranger', 'Chord', 'Arp' }
  grid_view_keys = {}
  grid_view_name = grid_views[2]
  pages = { 'GLOBAL>', 'CHORD', 'ARP', 'MIDI HARMONIZER', '<CV HARMONIZER' }
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  update_menus()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  -- generator_menus = {}
  -- generator_menu_index = 1 -- No top level option (yet)
  -- selected_generator_menu = generator_menus[generator_menu_index]

  transport_active = false
  pattern_length = { 4, 4, 4, 4 } -- loop length for each of the 4 patterns. rename to chord_seq_length prob
  pattern = 1
  pattern_name = { 'A', 'B', 'C', 'D' }
  steps_remaining_in_pattern = pattern_length[pattern]
  pattern_queue = false
  arranger_queue = false
  pattern_copy_performed = false
  arranger_seq_retrig = false
  -- Raw arranger_seq which can contain 0 patterns
  arranger_seq = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  -- Version of arranger_seq which generates chord patterns for held segments
  arranger_seq_padded = {}
  arranger_seq_position = 0
  arranger_seq_length = 1
  max_arranger_seq_length = 16
  generate_arranger_seq_padded()
  automator_events = {}
  for patt = 1, max_arranger_seq_length do
    automator_events[patt] = {}
    for step = 1, 8 do
      automator_events[patt][step] = {}
    end
  end
  automator_events_index = 1
  selected_automator_events_menu = 'event_category'

  -- Used to derive the min and max indices for the selected event category (Global, Chord, Arp, etc...)
  event_categories = {} -- to-do: make local after debug
  for i = 1, #events_lookup do
    event_categories[i] = events_lookup[i].category
  end
  set_event_category_min_max()
  params:set('event_name', event_category_min_index) -- Overwrites initial value
  event_edit_pattern = 0
  event_edit_step = 0
  event_edit_lane = 0
  steps_remaining_in_arrangement = 0
  elapsed = 0
  percent_step_elapsed = 0
  seconds_remaining_in_arrangement = 0
  chord_no = 0
  arranger_loop_key_count = 0
  pattern_keys = {}
  pattern_key_count = 0
  chord_key_count = 0
  view_key_count = 0
  event_key_count = 0
  keys = {}
  key_count = 0
  global_clock_div = 48
  chord_seq = { {}, {}, {}, {} }
  for p = 1, 4 do
    for i = 1, 8 do
      chord_seq[p][i] = { x = 0 } -- raw value
      chord_seq[p][i]["c"] = 0    -- chord wrapped 1-7
      chord_seq[p][i]["o"] = 0    -- octave
    end
  end
  chord_seq_position = 0
  readout_chord_seq_position = 0
  chord = {}
  chord = musicutil.generate_chord_scale_degree(chord_seq[pattern][1].o * 12, params:get('mode'), chord_seq[pattern][1]
    .c, true)
  current_chord_o = 0
  current_chord_c = 1
  next_chord_o = 0
  next_chord_c = 1
  arp_seq = { { 0, 0, 0, 0, 0, 0, 0, 0 },
    { 8, 8, 8, 8, 8, 8, 8, 8 },
    { 8, 8, 8, 8, 8, 8, 8, 8 },
    { 8, 8, 8, 8, 8, 8, 8, 8 }
  } -- sub table for multiple arp patterns
  arp_pattern_length = { 8, 8, 8, 8 }
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
  midi_note_history = {}
  engine_note_history = {}
  crow_note_history = {}
  jf_note_history = {}
  disting_note_history = {}
  reset_clock() -- will turn over to step 0 on first loop
  -- get_next_chord() -- Placeholder for when table loading from file is implemented
  next_chord = chord
  params:bang()
  -- Some actions need to occur post-bang
  params:set_action('mode', function() update_chord_action() end)
  grid_redraw()
  redraw()
end

-- UPDATE_MENUS. To-do: Probably can be optimized by only calculating the current view+page
function update_menus()
  -- EVENTS MENU
  local event_index = params:get('event_name')
  local value_type = events_lookup[event_index].value_type
  if value_type == 'inc, set' then
    automator_events_menus = { 'event_category', 'event_name', 'event_value_type', 'event_value' }
  elseif value_type == 'set' then
    automator_events_menus = { 'event_category', 'event_name', 'event_value' }
  elseif value_type == 'trigger' then
    automator_events_menus = { 'event_category', 'event_name' }
  end

  -- GLOBAL MENU
  menus[1] = { 'mode', 'transpose', 'clock_tempo', 'clock_source',
    --'clock_midi_out', --'clock_midi_out' option removed for Norns update with multi-clock. TBD if we should replicate all ports here (this could get cluttered)
    'chord_preload', 'chord_generator', 'arp_generator' }

  menus[2] = { 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index' }
  menus[3] = { 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_mode', }
  menus[4] = { 'midi_chord_type', 'midi_octave' }
  menus[5] = { 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest' }
end

function div_to_index(string)
  for i = 1, #division_names do
    if tab.key(division_names[i], string) == 2 then
      return (i)
    end
  end
end

-- This previously was used to define a single destination for sending out MIDI clock (and transport). Now we're using this to look up the system clock destinations and logging those so we send transport messages to all destinations. Fix: this gets called a lot just to be safe, but is probably only needed when the clock params are touched (callback?) or when starting transport.
function transport_midi_update()
  -- Find out which ports Norns is sending MIDI clock on so we know where to send transport messages
  midi_transport_ports = {}
  midi_transport_ports_index = 1
  for i = 1, 16 do
    if params:get('clock_midi_out_' .. i) == 1 then
      -- print('clock to port ' .. i)
      midi_transport_ports[midi_transport_ports_index] = i
      midi_transport_ports_index = midi_transport_ports_index + 1
    end
  end
end

-- check which ports the global midi clock is being sent to and sends a start message there
function transport_multi_start()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  -- for i in pairs(midi_transport_ports) do
  for i = 1, #midi_transport_ports do
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:start()
  end
end

-- check which ports the global midi clock is being sent to and sends a stop message there
function transport_multi_stop()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  for i in pairs(midi_transport_ports) do
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:stop()
  end
end

-- check which ports the global midi clock is being sent to and sends a continue message there
function transport_multi_continue()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  for i in pairs(midi_transport_ports) do
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:continue()
  end
end

function first_to_upper(str)
  return (str:gsub("^%l", string.upper))
end

function divisions_string(index)
  if index == 0 then return ('Off') else return (division_names[index][2]) end
end

--Creates a variable for each source's div.
function set_div(source)
  _G[source .. '_div'] = division_names[params:get(source .. '_div_index')][1]
end

--Creates a variable for each source's duration
function set_duration(source)
  _G[source .. '_duration'] = division_names[params:get(source .. '_duration_index')][1]
end

function duration_sec(dur_mod)
  return (dur_mod / global_clock_div * clock.get_beat_sec())
end

function param_id_to_name(id)
  -- print("trying id", id)
  return (params.params[params.lookup[id]].name)
end

function mode_index_to_name(index)
  return (musicutil.SCALES[index].name)
end

function round(num, numDecimalPlaces)
  local mult = 10 ^ (numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

function t_f_string(x)
  return (x == 1 and 'True' or 'False')
end

function transpose_string(x)
  local keys = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#',
    'G', 'G#', 'A', 'A#', 'B', 'C' }
  return (keys[x + 13] .. (x == 0 and '' or ' ') .. (x >= 1 and '+' or '') .. (x ~= 0 and x or ''))
end

function t_f_bool(x)
  return (x == 1 and true or false)
end

function div_10(x)
  return (x / 10)
end

function mult_100_percent(x)
  return (math.floor(x * 100) .. '%')
end

function percent(x)
  return (math.floor(x) .. '%')
end

function chord_type(x)
  return (x == 3 and 'Triad' or '7th')
end

function chord_preload(index)
  chord_preload_tics = (index == 0) and 0 or division_names[index][1]
end

function percent_chance(percent)
  return percent >= math.random(1, 100)
end

function clear_chord_pattern()
  for i = 1, 8 do
    chord_seq[pattern][i].x = 0
    chord_seq[pattern][i].c = 0
    chord_seq[pattern][i].o = 0
  end
end

function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

-- Pads out arranger where it has 0 segments
-- Called when selecting/deselecting Arranger segments, changing Arranger lenth via key or enc (insert/delete), switching patterns manually
function generate_arranger_seq_padded()
  arranger_seq_padded = {}

  -- First identify the first and last populated segments
  first_populated_segment = 0
  last_populated_segment = 0
  patt = nil

  -- To-do: this seems like a super crappy way to find the lowest and highest keys in arranger_seq?
  for k, v in pairs(arranger_seq) do
    if arranger_seq[k] > 0 then
      if first_populated_segment == 0 then first_populated_segment = k end
      last_populated_segment = math.max(last_populated_segment, k)
    end
  end

  arranger_seq_length = math.max(last_populated_segment, 1)

  -- Run this as a second loop since the above needs to iterate through all segments to update vars and set arranger_seq_length
  for i = 1, arranger_seq_length do
    -- First, let's handle any zeroed segments at the beginning of the sequence. Since the Arranger can be looped, we use the last populated segment where possible, then fall back on the current Pattern. Otherwise we would have a situation where the initial pattern potentially changes upon looping which is not very intuitive.
    if i < (first_populated_segment) then
      arranger_seq_padded[i] = arranger_seq[last_populated_segment] or pattern
      -- From this point on, we log the current segment's pattern so it can be used to propagate the pattern, then set this on the current step.
    elseif (arranger_seq[i] or 0) > 0 then
      patt = arranger_seq[i]
      arranger_seq_padded[i] = patt
    else
      arranger_seq_padded[i] = (patt or pattern)
    end
  end
end

-- Hacking up MusicUtil.generate_chord_roman to get modified chord_type for chords.
-- Could probably gain some efficiency by just writing all this to a table
-- @treturn chord_type
function get_chord_name(root_num, scale_type, roman_chord_type)
  local rct = roman_chord_type or "I"

  -- treat extended ascii degree symbols as asterisks
  rct = string.gsub(rct, "\u{B0}", "*")
  rct = string.gsub(rct, "\u{BA}", "*")

  local degree_string, augdim_string, added_string, bass_string, inv_string =
      string.match(rct, "([ivxIVX]+)([+*]?)([0-9]*)-?([0-9]?)([bcdefg]?)")

  local d = string.lower(degree_string)
  local is_major = degree_string ~= d
  local is_augmented = augdim_string == "+"
  local is_diminished = augdim_string == "*"
  local is_seventh = added_string == "7"

  local chord_type = nil
  if is_major then
    if is_augmented then
      if is_seventh then
        chord_type = "aug7"
      else
        chord_type = "aug"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = "dim7"
      else
        chord_type = "dim"
      end
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "maj69"
      else
        chord_type = "maj6"
      end
    elseif is_seventh then
      chord_type = "maj7"
    elseif added_string == "9" then
      chord_type = "maj9"
    elseif added_string == "11" then
      chord_type = "maj11"
    elseif added_string == "13" then
      chord_type = "maj13"
    else
      chord_type = "maj"
    end
  else -- minor
    if is_augmented then
      if is_seventh then
        chord_type = "aug7"
      else
        chord_type = "aug"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = "dim7"
      else
        chord_type = "dim"
      end
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "min69"
      else
        chord_type = "min6"
      end
    elseif is_seventh then
      chord_type = "min7"
    elseif added_string == "9" then
      chord_type = "min9"
    elseif added_string == "11" then
      chord_type = "min11"
    elseif added_string == "13" then
      chord_type = "min13"
    else
      chord_type = "min"
    end
  end
  return (chord_type)
end

-- Clock to control sequence events including chord pre-load, chord/arp sequence, and crow clock out
function sequence_clock()
  -- -- Optional count-in for when syncing to external MIDI/Link
  -- if params:string('clock_source') ~= 'internal' and params:get('count_in') > 0 then
  --   clock.sync(params:get('count_in'))
  -- end

  while transport_active do
    -- Moving syncing to beginning of while-do loop 2023-04-11. In testing, it seems that you can get better latency when syncing to an external MIDI source when syncing at the end of the loop but this is probably Bad for some reason.
    clock.sync(1 / global_clock_div)

    if start == true and stop ~= true then
      -- Send out MIDI start/continue messages
      -- transport_midi_update()
      -- if params:get('clock_midi_out_1') ~= 1 then
      if clock_start_method == 'start' then
        -- transport_midi:start()
        transport_multi_start()
      else
        -- transport_midi:continue()
        transport_multi_continue()
      end
      -- end
      clock_start_method = 'continue'
      start = false
    end


    -- ADVANCE CLOCK_STEP
    -- Wrap not strictly needed and could actually be used to count arranger position?
    -- 192 tics per measure * 8 (max a step can be, 0-indexed.
    clock_step = util.wrap(clock_step + 1, 0, 1535)


    -- STOP beat-quantized
    if stop == true then
      -- When internally clocked, stop is quantized to occur at the end of the beat
      -- Default quantization is global_clock_div * 4 to stop at end of measure
      -- To-do: add param for quantizing transport stop in different time signatures
      if params:string('clock_source') == 'internal' then
        if (clock_step) % (global_clock_div * 4) == 0 then --stops at the end of the beat
          print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: ' .. clock_start_method)
          -- Reset the clock_step so sequence_clock resumes at the same position as MIDI beat clock
          clock_step = util.wrap(clock_step - 1, 0, 1535)
          print('clock_step reset to ' .. clock_step)
          transport_multi_stop()
          print('Canceling clock_id ' .. (sequence_clock_id or 0))
          clock.cancel(sequence_clock_id) -- or 0)
          transport_active = false
          stop = false
        end
      else -- External clock_source. No quantization. Just resets pattern/arrangement
        transport_multi_stop()
        print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: ' .. clock_start_method)
        print('Canceling clock_id ' .. (sequence_clock_id or 0))
        clock.cancel(sequence_clock_id) -- or 0)

        if arranger_enabled then
          reset_arrangement()
        else
          reset_pattern()
        end

        transport_active = false
        stop = false
      end
    end

    -- Checking transport state again in case transport was just set to 'false' by Stop
    if transport_active then
      if util.wrap(clock_step + chord_preload_tics, 0, 1535) % chord_div == 0 then
        get_next_chord()
      end

      if clock_step % chord_div == 0 then
        advance_chord_seq()
        grid_dirty = true
        redraw() -- To update chord readout
      end

      if clock_step % arp_div == 0 then
        if params:string('arp_mode') == 'Loop' or play_arp then
          advance_arp_seq()
          grid_dirty = true
        end
      end
    end

    if grid_dirty == true then
      grid_redraw()
      grid_dirty = false
    end
  end
end

-- Clock used to redraw screen 10x a second for arranger countdown timer
-- To-do: Ideally only needs to fire once a second but the potential for it to get out of sync (tempo changes, reset, Generator) causes issues.
-- Might create a reinitialization function to call when needed (param actions and when resetting etc...)
function seconds_clock()
  while true do
    redraw()
    clock.sleep(.1)
  end
end

function clock.transport.start()
  print('Transport starting')
  start = true
  transport_active = true

  -- Clock for chord/arp/arranger sequences
  sequence_clock_id = clock.run(sequence_clock)

  --Clock used to refresh screen once a second for the arranger countdown timer
  clock.cancel(seconds_clock_id or 0)
  seconds_clock_id = clock.run(seconds_clock)
end

function clock.transport.stop()
  stop = true
end

-- Does not set start = true since this can be called by clock.transport.stop() when pausing
function reset_pattern() -- To-do: Also have the chord readout updated (move from advance_chord_seq to a function)
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  reset_clock()
  get_next_chord()
  chord = next_chord
  grid_redraw()
  redraw()
end

-- Does not set start = true since this can be called by clock.transport.stop() when pausing
function reset_arrangement()             -- To-do: Also have the chord readout updated (move from advance_chord_seq to a function)
  arranger_queue = nil
  arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  readout_chord_seq_position = 0
  arranger_seq_position = 0

  if arranger_seq[1] > 0 then pattern = arranger_seq[1] end

  if params:string('arranger_enabled') == 'True' then arranger_enabled = true end
  reset_clock()
  get_next_chord()
  chord = next_chord
  grid_redraw()
  redraw()
end

function reset_clock()
  clock_step = -1
  -- Immediately update this so if Arranger is zeroed we can use the current-set pattern (even if paused)
  generate_arranger_seq_padded()
end

-- Used when resetting view K3 or when jumping to chord pattern immediately via g.key press
function reset_external_clock()
  -- If we're sending MIDI clock out, send a stop msg
  -- Tell the transport to Start on the next sync of sequence_clock
  if transport_active then
    transport_multi_stop()
  end
  -- Tell sequence_clock to send a MIDI start/continue message after initial clock sync
  clock_start_method = 'start'
  start = true
end

function advance_chord_seq()
  chord_seq_retrig = true -- indicates when we're on a new chord seq step for crow auto-rest logic.
  play_arp = true
  local arrangement_reset = false

  -- Advance arranger sequence if enabled
  if params:string('arranger_enabled') == 'True' then
    -- If it's post-reset or at the end of chord sequence
    -- TODO: Really need a global var for when in a reset state (arranger_seq_position == 0 and chord_seq_position == 0)
    if (arranger_seq_position == 0 and chord_seq_position == 0) or chord_seq_position >= pattern_length[pattern] then
      -- This variable is only set when the 'arranger_enabled' param is 'True' and we're moving into a new Arranger segment (or after reset)
      arranger_enabled = true

      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        arrangement_reset = true
        reset_arrangement()
        clock.transport.stop()
      else
        -- changed from wrap to a check if incremented arranger_seq_position exceeds seq_length
        arranger_seq_position = arranger_seq_padded[arranger_queue] ~= nil and arranger_queue or
            (arranger_seq_position + 1 > arranger_seq_length) and 1 or arranger_seq_position + 1
        pattern = arranger_seq_padded[arranger_seq_position]
        arranger_queue = nil
      end

      -- Indicates arranger has moved to new pattern.
      arranger_seq_retrig = true
    end
    -- Flag if arranger is on the last pattern of a 1-shot sequence
    arranger_ending()
  end

  -- If arrangement was not just reset, update chord position.
  if arrangement_reset == false then
    if chord_seq_position >= pattern_length[pattern] or arranger_seq_retrig then
      if pattern_queue then
        pattern = pattern_queue
        pattern_queue = false
      end
      chord_seq_position = 1
      arranger_seq_retrig = false
    else
      chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
    end

    if arranger_enabled then readout_chord_seq_position = chord_seq_position end

    -- Arranger automation step. To-do: also need to have some events fire on get_next_chord.
    if arranger_enabled then automator() end
    update_chord()

    -- Play the chord
    if chord_seq[pattern][chord_seq_position].c > 0 then play_chord() end

    if chord_key_count == 0 then
      chord_no = current_chord_c + (params:get('chord_type') == 4 and 7 or 0)
      generate_chord_names()
    end
  end
end

function arranger_ending()
  arranger_one_shot_last_pattern = arranger_seq_position >= arranger_seq_length and
      params:string('playback') == 'One-shot'
end

-- Checks each time arrange_enabled param changes to see if we need to also immediately set the corresponding arranger_enabled var to false. arranger_enabled will be false until Arranger is re-synched/resumed.
-- Also sets pattern_queue to false to clear anything previously set
function update_arranger_enabled()
  if params:string('arranger_enabled') == 'False' then
    arranger_enabled = false
  elseif params:string('arranger_enabled') == 'True' then
    if chord_seq_position == 0 then arranger_enabled = true end
    pattern_queue = false
  end
end

function automator()
  if automator_events[arranger_seq_position] ~= nil and arranger_seq_position ~= 0 and chord_seq_position ~= 0 then
    if automator_events[arranger_seq_position][chord_seq_position].populated or 0 > 0 then
      for i = 1, 16 do
        -- To-do: Cheesy check if each automation event lane has something. This sucks.
        if automator_events[arranger_seq_position][chord_seq_position][i] ~= nil then
          local event_type = automator_events[arranger_seq_position][chord_seq_position][i].event_type
          local event_name = events_lookup[automator_events[arranger_seq_position][chord_seq_position][i].event_index]
              .id
          local value = automator_events[arranger_seq_position][chord_seq_position][i].event_value or ''
          local value_type_index = automator_events[arranger_seq_position][chord_seq_position][i].event_value_type
          local value_type = params.params[params.lookup['event_value_type']]['options'][value_type_index] or ''
          local action = automator_events[arranger_seq_position][chord_seq_position][i].action or nil
          local action_var = automator_events[arranger_seq_position][chord_seq_position][i].action_var or nil

          -- debuggin'
          -- print('event_type: ' .. event_type)
          -- print('event_name: ' .. event_name)
          -- print('value: ' .. value)
          -- print('value_type_index: ' .. value_type_index)
          -- print('value_type: ' .. value_type)

          if event_type == 'param' then
            params:set(event_name, (value + (value_type == 'Increment' and params:get(event_name) or 0)))
          else -- functions
            _G[event_name](value)
          end

          if action ~= nil then
            _G[action](action_var)
          end
        end
      end
    end
  end
end

function generate_chord_names()
  if chord_no > 0 then
    chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_no]
    --To-do: More thoughtful display of either sharps or flats depending on specific chord and key. I need someone that is not a musical hack (me) to explain how this works.
    chord_name = musicutil.NOTE_NAMES
        [util.wrap((musicutil.SCALES[params:get('mode')]['intervals'][util.wrap(chord_no, 1, 7)] + 1) + params:get('transpose'), 1, 12)]
    chord_name_modifier = get_chord_name(1 + 1, params:get('mode'), chord_degree) -- transpose root?
  end
end

function update_chord()
  -- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord.
  -- Mode is always updated in case no chord has been set but user has changed Mode param.
  current_chord_o = chord_seq[pattern][chord_seq_position].c > 0 and chord_seq[pattern][chord_seq_position].o or
      current_chord_o
  current_chord_c = chord_seq[pattern][chord_seq_position].c > 0 and chord_seq[pattern][chord_seq_position].c or
      current_chord_c
  chord = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  -- chord transformations
  invert_chord()
  spread_chord()
end

-- Makes a copy of the base chord table with inversion applied
function invert_chord()
  chord_inverted = {}
  for i = 1, params:get('chord_type') do
    chord_inverted[i] = chord[i]
  end

  if params:get('chord_inversion') ~= 0 then
    for i = 1, params:get('chord_inversion') do
      local index = util.wrap(i, 1, #chord_inverted) --params:get('chord_type'))
      chord_inverted[index] = chord_inverted[index] + 12
    end
    -- Re-sort them so we can apply additional transformations later
    table.sort(chord_inverted)
  end
end

-- Applies note spread to chord (in octaves)
function spread_chord()
  -- chord_inverted = deepcopy(chord)
  if params:get('chord_spread') ~= 0 then
    for i = 1, #chord_inverted do
      chord_inverted[i] = chord_inverted[i] +
          round((params:get('chord_spread') / (params:get('chord_type') - 1) * (i - 1))) * 12
    end
  end
end

-- Simpler chord update that just picks up the current mode (for param actions)
function update_chord_action()
  chord = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
end

function play_chord()
  local player = params:lookup_param("chord_voice"):get_player()
  for i = 1, params:get('chord_type') do
    local note = chord_inverted[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
    player:play_note(note, 0.5, chord_duration / 96)
  end
end

-- Pre-load upcoming chord to address race condition around quantize_note() events occurring before chord change
function get_next_chord()
  local pre_arrangement_reset = false
  local pre_arranger_seq_position = arranger_seq_position
  local pre_arranger_seq_retrig = arranger_seq_retrig
  local pre_chord_seq_position = chord_seq_position
  local pre_pattern_queue = pattern_queue
  pre_pattern = pattern

  -- Move arranger sequence if enabled
  if params:get('arranger_enabled') == 1 then
    -- If it's post-reset or at the end of chord sequence
    if (pre_arranger_seq_position == 0 and pre_chord_seq_position == 0) or pre_chord_seq_position >= pattern_length[pre_pattern] then
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        pre_arrangement_reset = true
      else
        pre_arranger_seq_position = arranger_seq_padded[arranger_queue] ~= nil and arranger_queue or
            util.wrap(pre_arranger_seq_position + 1, 1, arranger_seq_length)
        pre_pattern = arranger_seq_padded[pre_arranger_seq_position]
      end

      -- Indicates arranger has moved to new pattern.
      pre_arranger_seq_retrig = true
    end
  end

  -- If arrangement was not just reset, update chord position.
  if pre_arrangement_reset == false then
    if pre_chord_seq_position >= pattern_length[pre_pattern] or pre_arranger_seq_retrig then
      if pre_pattern_queue then
        pre_pattern = pre_pattern_queue
        pre_pattern_queue = false
      end
      pre_chord_seq_position = 1
      pre_arranger_seq_retrig = false
    else
      pre_chord_seq_position = util.wrap(pre_chord_seq_position + 1, 1, pattern_length[pre_pattern])
    end

    -- Arranger automation step. To-do: examine impact of running some events here rather than in advance_chord_seq
    -- Could be important for anything that changes patterns but might also be weird for grid redraw
    -- if params:get('arranger_enabled') == 1 and (arranger_seq[pre_arranger_seq_position] or 0) > 0 then
    --   automator()
    -- end

    -- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord.
    -- Mode is always updated in case no chord has been set but user has changed Mode param.
    next_chord_o = chord_seq[pre_pattern][pre_chord_seq_position].c > 0 and
        chord_seq[pre_pattern][pre_chord_seq_position].o or next_chord_o
    next_chord_c = chord_seq[pre_pattern][pre_chord_seq_position].c > 0 and
        chord_seq[pre_pattern][pre_chord_seq_position].c or next_chord_c
    next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
  end
end

-- Used for CV/MIDI harmonizers to quantize per upcoming chord.
function pre_quantize_note(note_num, source)
  local chord_length = params:get(source .. '_chord_type') -- Move upstream?
  local source_octave = params:get(source .. '_octave')    -- Move upstream?
  local quantized_note = next_chord[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return (quantized_note + ((source_octave + quantized_octave) * 12) + params:get('transpose'))
end

function quantize_note(note_num, source)
  local chord_length = params:get(source .. '_chord_type') -- Move upstream?
  local source_octave = params:get(source .. '_octave')    -- Move upstream?
  local quantized_note = chord[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return (quantized_note + ((source_octave + quantized_octave) * 12) + params:get('transpose'))
end

function advance_arp_seq()
  if arp_seq_position > arp_pattern_length[arp_pattern] or arranger_seq_retrig == true then
    arp_seq_position = 1
  else
    arp_seq_position = util.wrap(arp_seq_position + 1, 1, arp_pattern_length[arp_pattern])
  end

  if arp_seq[arp_pattern][arp_seq_position] > 0 then
    local player = params:lookup_param("arp_voice"):get_player()
    local note = quantize_note(arp_seq[arp_pattern][arp_seq_position], 'arp')
    player:play_note(note, 0.5, arp_duration / 96)
  end

  if params:string('arp_mode') == 'One-shot' and arp_seq_position >= arp_pattern_length[arp_pattern] then
    play_arp = false
  else
  end
end

function crow_trigger()                                                          --Trigger in used to sample voltage from Crow IN 1
  crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
  crow.input[1].query()                                                          -- see https://github.com/monome/crow/pull/463
end

function sample_crow(volts)
  local note = params:get('chord_preload') == 0 and quantize_note(round(volts * 12, 0) + 1, 'crow') or
      pre_quantize_note(round(volts * 12, 0) + 1, 'crow')

  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_seq_retrig == true
      or params:get('do_crow_auto_rest') == 0
      or (params:get('do_crow_auto_rest') == 1 and (prev_note ~= note)) then
    local player = params:lookup_param("crow_voice"):get_player()
    player:play_note(note, 0.5, crow_duration / 96)
  end

  prev_note = note
  chord_seq_retrig = false -- Resets at chord advance
end

function grid_redraw()
  g:all(0)

  -- Events supercedes other views
  if screen_view_name == 'Events' then
    -- Draw grid with 16 event lanes (columns) for each step in the selected pattern
    for x = 1, 16 do  -- event lanes
      for y = 1, 8 do -- pattern steps
        g:led(x, y,
          (automator_events[event_edit_pattern][y][x] ~= nil and 7 or (y > (pattern_length[arranger_seq_padded[event_edit_pattern]] or 0) and 0 or 2)))
        if y == event_edit_step and x == event_edit_lane then
          g:led(x, y, 15)
        end
      end
    end
  else
    for i = 6, 8 do
      g:led(16, i, 4)
    end

    for i = 1, #grid_view_keys do
      g:led(16, grid_view_keys[i], 7)
    end

    if grid_view_name == 'Arranger' then
      g:led(16, 6, 15)

      for x = 1, max_arranger_seq_length do
        for y = 1, 4 do
          g:led(x, y,
            x == arranger_seq_position and 6 or x == arranger_queue and 4 or x <= arranger_seq_length and 2 or 0)
          if y == arranger_seq_padded[x] then g:led(x, y, x == arranger_seq_position and 9 or 7) end
          if y == arranger_seq[x] then g:led(x, y, 15) end
        end
        g:led(x, 5,
          (automator_events[x] ~= nil and automator_events[x].populated or 0) > 0 and 15 or x > arranger_seq_length and 3 or
          7)
      end

      g:led(1, 8, params:get('arranger_enabled') == 1 and 15 or 4)
      -- Optionally: Arranger enable/disable key has 3 states. on/re-sync/off
      -- if params:get('arranger_enabled') == 1 then
      -- if arranger_enabled == false then
      --   g:led(1,8, math.random(12,15))
      -- else
      -- g:led(1,8, 15)
      -- end
      -- else
      -- g:led(1,8, 4)
      -- end

      g:led(2, 8, params:get('playback') == 1 and 15 or 4)
    elseif grid_view_name == 'Chord' then
      if params:string('arranger_enabled') == 'True' and arranger_one_shot_last_pattern == false then
        next_pattern_indicator = arranger_seq_padded[util.wrap(arranger_seq_position + 1, 1, arranger_seq_length)]
      else
        next_pattern_indicator = pattern_queue or pattern
      end
      for i = 1, 4 do
        g:led(16, i, i == next_pattern_indicator and 7 or pattern_keys[i] and 7 or 3)
        if i == pattern then
          g:led(16, i, 15)
        end
      end
      g:led(16, 7, 15)
      for i = 1, 14 do -- chord seq playhead
        g:led(i, chord_seq_position, 3)
      end
      for i = 1, 8 do
        g:led(15, i, pattern_length[pattern] < i and 4 or 15) --set pattern_length LEDs
        if chord_seq[pattern][i].x > 0 then                   -- muted steps
          g:led(chord_seq[pattern][i].x, i, 15)               -- set LEDs for chord sequence
        end
      end
    elseif grid_view_name == 'Arp' then
      g:led(16, 8, 15)
      for i = 1, 14 do -- chord seq playhead
        g:led(i, arp_seq_position, 3)
      end
      for i = 1, 8 do
        g:led(15, i, arp_pattern_length[arp_pattern] < i and 4 or 15) --set pattern_length LEDs
        if arp_seq[arp_pattern][i] > 0 then                           -- muted steps
          g:led(arp_seq[arp_pattern][i], i, 15)                       --set LEDs for arp sequence
        end
      end
    end
  end
  g:refresh()
end

-- GRID KEYS
function g.key(x, y, z)
  if z == 1 then
    if screen_view_name == 'Events' then
      -- Setting of events past the pattern length is permitted
      event_key_count = event_key_count + 1
      -- First touched event is the one we edit, effectively resetting on key_count = 0
      if event_key_count == 1 then
        event_edit_step = y
        event_edit_lane = x
        event_saved = false
        -- If the event lane is populated, Load the Event vars back to the displayed param
        if automator_events[event_edit_pattern][y][x] ~= nil then
          local event_category_options = params.params[params.lookup['event_category']].options
          params:set('event_category',
            tab.key(event_category_options, automator_events[event_edit_pattern][y][x].category))
          set_event_category_min_max()
          params:set('event_name', automator_events[event_edit_pattern][y][x].event_index)
          if automator_events[event_edit_pattern][y][x].event_value ~= nil then
            params:set('event_value', automator_events[event_edit_pattern][y][x].event_value)
            if automator_events[event_edit_pattern][y][x].event_value_type ~= nil then
              params:set('event_value_type', automator_events[event_edit_pattern][y][x].event_value_type)
            end
          end
          event_name = events_lookup[params:get('event_name')].id
        else
          event_name = events_lookup[params:get('event_name')].id
          set_event_range()
          init_event_value()
        end

        event_edit_active = true
      else -- Subsequent keys down paste event
        -- But first check if the events we're working with are populated
        local og_event_populated = automator_events[event_edit_pattern][y][x] ~= nil
        local copied_event_populated = automator_events[event_edit_pattern][event_edit_step][event_edit_lane] ~= nil

        -- Then copy
        automator_events[event_edit_pattern][y][x] = deepcopy(automator_events[event_edit_pattern][event_edit_step]
          [event_edit_lane])

        -- Adjust populated events count at the step level. To-do: also set at the segment level once implemented
        if og_event_populated and not copied_event_populated then
          automator_events[event_edit_pattern][y].populated = automator_events[event_edit_pattern][y].populated - 1

          -- If the step's new populated count == 0, decrement count of populated event STEPS in the segment
          if (automator_events[event_edit_pattern][y].populated or 0) == 0 then
            automator_events[event_edit_pattern].populated = (automator_events[event_edit_pattern].populated or 0) - 1
          end
        elseif not og_event_populated and copied_event_populated then
          automator_events[event_edit_pattern][y].populated = (automator_events[event_edit_pattern][y].populated or 0) +
              1

          -- If this is the first event to be added to this step, increment count of populated event STEPS in the segment
          if (automator_events[event_edit_pattern][y].populated or 0) == 1 then
            print('incrementing segment populated')
            automator_events[event_edit_pattern].populated = (automator_events[event_edit_pattern].populated or 0) + 1
          end
        end

        print('Copy+paste event from segment ' ..
          event_edit_pattern ..
          '.' ..
          event_edit_step .. ' lane ' .. event_edit_lane .. ' to ' .. event_edit_pattern .. '.' .. y .. ' lane ' .. x)
      end

      -- view_key buttons
    elseif x == 16 and y > 5 then
      view_key_count = view_key_count + 1
      table.insert(grid_view_keys, y)
      if view_key_count == 1 then
        grid_view_name = grid_views[y - 5]
      elseif view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
        screen_view_name = 'Chord+arp'
      end

      --ARRANGER KEY DOWN-------------------------------------------------------
    elseif grid_view_name == 'Arranger' then
      -- enable/disable Arranger
      if x == 1 and y == 8 then
        if params:get('arranger_enabled') == 0 then
          params:set('arranger_enabled', 1)
        else
          params:set('arranger_enabled', 0)
        end

        -- enable/disable Arranger playback Loop mode
      elseif x == 2 and y == 8 then
        if params:get('playback') == 1 then
          params:set('playback', 2)
        else
          params:set('playback', 1)
        end

        -- Automator events strip key down
      elseif y == 5 then
        arranger_loop_key_count = arranger_loop_key_count + 1

        -- Initial key down copies stuff. First touched pattern is the one we edit, effectively resetting on key_count = 0
        if arranger_loop_key_count == 1 then
          event_edit_pattern = x

          -- Store original arranger sequence values so we can have non-destructive pattern shifting using ENC 3
          d_cuml = 0
          arranger_seq_length_og = arranger_seq_length
          arranger_seq_og = deepcopy(arranger_seq)
          automator_events_og = deepcopy(automator_events)
          event_edit_pattern_og = event_edit_pattern

          -- Subsequent keys down paste all automator events in segment, but not the segment pattern
        else
          automator_events[x] = deepcopy(automator_events[event_edit_pattern])
          print('Copy+paste events from segment ' .. event_edit_pattern .. ' to segment ' .. x)
        end

        -- Arranger_seq patterns
      elseif y < 5 then
        if y == arranger_seq[x] then
          arranger_seq[x] = 0
        else
          arranger_seq[x] = y
        end
        generate_arranger_seq_padded()
      end
      if transport_active == false then -- Update chord for when play starts
        get_next_chord()
        chord = next_chord
      end

      --CHORD KEYS
    elseif grid_view_name == 'Chord' then
      if x < 15 then
        chord_key_count = chord_key_count + 1
        if x == chord_seq[pattern][y].x then
          chord_seq[pattern][y].x = 0
          chord_seq[pattern][y].c = 0
          chord_seq[pattern][y].o = 0
        else
          chord_seq[pattern][y].x = x                                              --raw key x coordinate
          chord_seq[pattern][y].c = util.wrap(x, 1, 7)                             --chord 1-7 (no octave). Should move this to a function since it's called a few places.
          chord_seq[pattern][y].o = math.floor(x / 8)                              --octave
        end
        chord_no = util.wrap(x, 1, 7) + (params:get('chord_type') == 4 and 7 or 0) -- or 0
        generate_chord_names()
      elseif x == 15 then
        pattern_length[pattern] = y
      elseif x == 16 and y < 5 then --Key DOWN events for pattern switcher. Key UP events farther down in function.
        pattern_key_count = pattern_key_count + 1
        pattern_keys[y] = 1
        if pattern_key_count == 1 then
          pattern_copy_source = y
        elseif pattern_key_count > 1 then
          print('Copying pattern ' .. pattern_copy_source .. ' to pattern ' .. y)
          pattern_copy_performed = true
          -- To-do: deepcopy
          for i = 1, 8 do
            chord_seq[y][i].x = chord_seq[pattern_copy_source][i].x
            chord_seq[y][i].c = chord_seq[pattern_copy_source][i].c
            chord_seq[y][i].o = chord_seq[pattern_copy_source][i].o
          end
          pattern_length[y] = pattern_length[pattern_copy_source]
        end
      end
      if transport_active == false then -- Pre-load chord for when play starts
        get_next_chord()
        chord = next_chord
      end

      -- ARP KEYS
    elseif grid_view_name == 'Arp' then
      if x < 15 then
        if x == arp_seq[arp_pattern][y] then
          arp_seq[arp_pattern][y] = 0
        else
          arp_seq[arp_pattern][y] = x
          grid_dirty = true
        end
      elseif x == 15 then
        arp_pattern_length[arp_pattern] = y
      end
    end

    --------------
    --G.KEY RELEASED
    --------------
  elseif z == 0 then
    -- Events key up
    if screen_view_name == 'Events' then
      event_key_count = math.max(event_key_count - 1, 0)

      -- Reset event_edit_step/lane when last key is released (if it was skipped when doing a K3 save to allow for copy+paste)
      if event_key_count == 0 and event_saved then
        event_edit_step = 0
        event_edit_lane = 0
      end

      -- view_key buttons
    elseif x == 16 and y > 5 then
      view_key_count = math.max(view_key_count - 1, 0)
      table.remove(grid_view_keys, tab.key(grid_view_keys, y))
      if view_key_count > 0 then
        grid_view_name = grid_views[grid_view_keys[1] - 5]

        if view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
          screen_view_name = 'Chord+arp'
        else
          screen_view_name = 'Session'
        end
      else
        screen_view_name = 'Session'
      end

      -- Chord key up
    elseif grid_view_name == 'Chord' then
      if x == 16 and y < 5 then
        pattern_key_count = math.max(pattern_key_count - 1, 0)
        pattern_keys[y] = nil
        if pattern_key_count == 0 and pattern_copy_performed == false then
          -- Resets current pattern immediately
          if y == pattern then
            print('a - manual reset of current pattern')
            params:set('arranger_enabled', 0)
            pattern_queue = false
            arp_seq_position = 0 -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_external_clock()
            reset_pattern()

            -- Manual jump to queued pattern
          elseif y == pattern_queue then
            print('b - manual jump to queued pattern')

            pattern_queue = false
            pattern = y
            arp_seq_position = 0 -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_external_clock()
            reset_pattern()

            -- Cue up a new pattern
          else
            print('c - new pattern queued')
            if pattern_copy_performed == false then
              pattern_queue = y
              params:set('arranger_enabled', 0)
            end
          end
        end
      elseif x < 15 then
        chord_key_count = chord_key_count - 1
        if chord_key_count == 0 then
          -- This reverts the chord readout to the currently loaded chord but it is kinda confusing when paused so now it just wipes and refreshes at the next chord step.
          -- chord_no = current_chord_c + (params:get('chord_type') == 4 and 7 or 0)
          -- generate_chord_names()
          chord_no = 0
        end
      end

      -- Arranger key up
    elseif grid_view_name == 'Arranger' then
      -- Arranger loop strip
      if y == 5 then
        arranger_loop_key_count = math.max(arranger_loop_key_count - 1, 0)
      end
    end

    -- -- GRID VIEW SWITCHER KEYS
    -- if x == 16 and y > 5 then
    --   view_key_count = view_key_count - 1
    -- end

    if pattern_key_count == 0 then
      pattern_copy_performed = false
    end
  end
  redraw()
  grid_redraw()
end

function key(n, z)
  if z == 1 then
    -- KEY 1 just increments keys and key_count to bring up alt menu (disabled currently but whatever)
    keys[n] = 1
    key_count = key_count + 1
    if n == 1 then
      -- Fn menu is displayed since keys[1] == 1

      -- KEY 2
    elseif n == 2 then
      if keys[1] == 1 then
        -- Nothing at the moment
        -- Arranger loop strip held down
      elseif arranger_loop_key_count > 0 then
        arranger_queue = event_edit_pattern
        grid_redraw()
      elseif screen_view_name == 'Events' then
        ------------------------
        -- K2 DELETE EVENT
        ------------------------
        if event_edit_active then
          -- Record the count of events on this step
          local event_count = automator_events[event_edit_pattern][event_edit_step].populated or 0

          -- Check if event is populated and needs to be deleted
          if automator_events[event_edit_pattern][event_edit_step][event_edit_lane] ~= nil then
            -- Decrement populated count at the step level
            automator_events[event_edit_pattern][event_edit_step].populated = event_count - 1

            -- If the step's new populated count == 0, update the segment level populated count
            if automator_events[event_edit_pattern][event_edit_step].populated == 0 then
              automator_events[event_edit_pattern].populated = automator_events[event_edit_pattern].populated - 1
            end

            -- Delete the event
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane] = nil
          end

          -- Back to event overview
          event_edit_active = false

          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true

          redraw()

          -- K2 here deletes ALL events in arranger SEGMENT
        else
          for step = 1, 8 do
            automator_events[event_edit_pattern][step] = {}
          end
          automator_events[event_edit_pattern].populated = 0

          screen_view_name = 'Session'
        end
        grid_redraw()

        -- Start/resume
      elseif params:string('clock_source') == 'internal' then
        if transport_active then
          clock.transport.stop()
          clock_start_method = 'continue'
          start = true
        else
          clock.transport.start()
        end
      end

      -- KEY 3
    elseif n == 3 then
      -- if keys[1] == 1 then

      if view_key_count > 0 then -- Grid view key held down
        if screen_view_name == 'Chord+arp' then
          -- When Chord+Arp Grid View keys are held down, K3 runs Generator and resets pattern+arp
          generator()

          -- If we're sending MIDI clock out, send a stop msg. This has changed with the multi clock Norns update. Needs testing.
          -- Tell the transport to Start on the next sync of sequence_clock
          if #midi_transport_ports > 0 then
            if transport_active then
              transport_multi_stop()
            end

            -- Tells sequence_clock to send a MIDI start/continue message after initial clock sync
            clock_start_method = 'start'
            start = true
          end

          -- For now, doing a pattern reset but not an arranger reset since it's confusing if we generate on, say, pattern 3 and then Arranger is reset and we're now on pattern 1.
          -- if params:get('arranger_enabled') == 1 then reset_arrangement() else reset_pattern() end
          reset_pattern()
        elseif grid_view_name == 'Chord' then
          chord_generator_lite()
        elseif grid_view_name == 'Arp' then
          arp_generator('run')
        end
        grid_redraw()

        ---------------------------------------------------------------------------
        -- K3 with Event Timeline key held down enters Event editor
        ---------------------------------------------------------------------------
      elseif arranger_loop_key_count > 0 then
        arranger_loop_key_count = 0
        event_edit_step = 0
        event_edit_lane = 0
        event_edit_active = false
        screen_view_name = 'Events'
        grid_redraw()

        -- K3 saves event to automator_events
      elseif screen_view_name == 'Events' then
        ---------------------------------------
        -- K3 TO SAVE EVENT
        ---------------------------------------
        print('event_edit_active ' .. (event_edit_active and 'true' or 'false'))
        if event_edit_active then
          local event_index = params:get('event_name')
          local event_id = events_lookup[event_index].id
          local event_type = events_lookup[event_index].event_type
          local event_value = params:get('event_value')
          local value_type = events_lookup[event_index].value_type
          local action = events_lookup[event_index].action
          local action_var = events_lookup[event_index].action_var

          -- Keep track of how many events are populated in this step so we don't have to iterate through them all later
          local step_event_count = automator_events[event_edit_pattern][event_edit_step].populated or 0

          -- If we're saving over a previously-nil event, increment the step populated count
          if automator_events[event_edit_pattern][event_edit_step][event_edit_lane] == nil then
            automator_events[event_edit_pattern][event_edit_step].populated = step_event_count + 1

            -- Also check to see if we need to increment the count of populated event STEPS in the SEGMENT
            if (automator_events[event_edit_pattern][event_edit_step].populated or 0) == 1 then
              automator_events[event_edit_pattern].populated = (automator_events[event_edit_pattern].populated or 0) + 1
            end
          end

          -- Wipe existing events, write the event vars to automator_events
          if value_type == 'trigger' then
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane] = {
              category = events_lookup[event_index].category, event_type = event_type, event_index = event_index }

            print('Saving Trigger event to automator_events[' ..
              event_edit_pattern .. '][' .. event_edit_step .. '][' .. event_edit_lane .. ']')
            print('category = ' ..
              events_lookup[event_index].category .. ', event_type = ' .. event_type .. ', event_index = ' .. event_index)
          elseif value_type == 'set' then
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane] = {
              category = events_lookup[event_index].category,
              event_type = event_type,
              event_index = event_index,
              event_value = event_value
            }

            print('Saving Set event to automator_events[' ..
              event_edit_pattern .. '][' .. event_edit_step .. '][' .. event_edit_lane .. ']')
            print('category = ' ..
              events_lookup[event_index].category ..
              ', event_type = ' .. event_type .. ', event_index = ' .. event_index .. ', event_value = ' .. event_value)
          elseif value_type == 'inc, set' then
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane] = {
              category = events_lookup[event_index].category,
              event_type = event_type,
              event_index = event_index,
              event_value = event_value,
              event_value_type = params:get('event_value_type')
            }

            print('Saving Inc/Set event to automator_events[' ..
              event_edit_pattern .. '][' .. event_edit_step .. '][' .. event_edit_lane .. ']')
            print('category = ' ..
              events_lookup[event_index].category ..
              ', event_type = ' ..
              event_type ..
              ', event_index = ' ..
              event_index ..
              ', event_value = ' .. event_value .. ' event_value_type = ' .. params:get('event_value_type'))
          end

          -- Extra fields are added if action is assigned to param/function
          if action ~= nil then
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane].action = action
            automator_events[event_edit_pattern][event_edit_step][event_edit_lane].action_var = action_var

            print('Action = ' .. action or '' .. '(' .. action_var or '' .. ')')
          end


          -- Back to event overview
          event_edit_active = false

          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true

          grid_redraw()
        else
          screen_view_name = 'Session'
          grid_redraw()
        end
      else
        -- Reset pattern/arp/arranger for standard K3 functionality-----------------
        reset_external_clock()

        -- To-do: think about this some. What behavior makes sense if a reset occurs while waiting for Arranger to re-sync?
        if params:get('arranger_enabled') == 1 then
          reset_arrangement()
        else
          reset_pattern()
        end
      end
    end
  elseif z == 0 then
    keys[n] = nil
    key_count = key_count - 1
  end
  redraw()
end

-- Rotate looping portion of pattern
function rotate_pattern(view, direction)
  if view == 'Chord' then
    local length = pattern_length[pattern]
    local temp_chord_seq = {}
    for i = 1, length do
      temp_chord_seq[i] = { x = chord_seq[pattern][i].x } -- I still don't get why this has to be formatted differently
      temp_chord_seq[i]['c'] = chord_seq[pattern][i].c
      temp_chord_seq[i]['o'] = chord_seq[pattern][i].o
    end
    for i = 1, length do
      chord_seq[pattern][i]['x'] = temp_chord_seq[util.wrap(i - direction, 1, length)].x
      chord_seq[pattern][i]['c'] = temp_chord_seq[util.wrap(i - direction, 1, length)].c
      chord_seq[pattern][i]['o'] = temp_chord_seq[util.wrap(i - direction, 1, length)].o
    end
  elseif view == 'Arp' then
    local length = arp_pattern_length[arp_pattern]
    local temp_arp_seq = {}
    for i = 1, length do
      temp_arp_seq[i] = arp_seq[arp_pattern][i]
    end
    for i = 1, length do
      arp_seq[arp_pattern][i] = temp_arp_seq[util.wrap(i - direction, 1, length)]
    end
  end
end

-- EVENT-SPECIFIC FUNCTIONS ------------------------------------------------------

-- Variation on the standard generators that will just run the algos and reset arp (but not pattern or arranger)
-- function generator_and_reset()
function event_gen()
  generator()
  arp_seq_position = 0
end

function event_chord_gen()
  chord_generator_lite()
  arp_seq_position = 0
end

function event_arp_gen()
  arp_generator('run')
  arp_seq_position = 0
end

function shuffle_arp()
  local shuffled_arp_seq = shuffle(arp_seq[arp_pattern])
  arp_seq[arp_pattern] = shuffled_arp_seq
end

-- Passes along 'Arp' var so we can have a specific event for just arp
function rotate_arp(direction)
  rotate_pattern('Arp', direction)
end

-- Event Crow trigger out
function crow_event_trigger()
  crow.output[4].action = 'pulse(.001,10,1)' -- (time,level,polarity)
  crow.output[4]()
end

-- for event triggers
function transpose_chord_pattern(direction)
  transpose_pattern('Chord', direction)
end

-- for event triggers
function transpose_arp_pattern(direction)
  transpose_pattern('Arp', direction)
end

-- "Transposes" pattern if you can call it that
function transpose_pattern(view, direction)
  if view == 'Chord' then
    for y = 1, 8 do
      if chord_seq[pattern][y]['x'] ~= 0 then
        chord_seq[pattern][y]['x'] = util.wrap(chord_seq[pattern][y]['x'] + direction, 1, 14)
        chord_seq[pattern][y].c = util.wrap(chord_seq[pattern][y]['x'], 1, 7) --chord 1-7 (no octave)
        chord_seq[pattern][y].o = math.floor(chord_seq[pattern][y]['x'] / 8)  --octave
      end
    end
  elseif view == 'Arp' then
    for y = 1, 8 do
      if arp_seq[arp_pattern][y] ~= 0 then
        arp_seq[arp_pattern][y] = util.wrap(arp_seq[arp_pattern][y] + direction, 1, 14)
      end
    end
  end
end

function set_event_category_min_max()
  -- Fetches the min and max index for the selected event category (Global, Chord, Arp, etc...)
  -- Also should be called when K3 opens events menu and when recalling a populated event slot
  event_category_min_index = tab.key(event_categories, params:string('event_category'))
  event_category_max_index = 0
  for i = 1, #event_categories do
    event_category_max_index = event_categories[i] == params:string('event_category') and i or event_category_max_index
  end
end

-- END OF EVENT-SPECIFIC FUNCTIONS ------------------------------------------------------


function enc(n, d)
  -- if keys[1] == 1 then -- fn key (KEY1) held down mode

  -- Reserved for scrolling/extending Arranger, Chord, Arp sequences
  if n == 1 then
    -- n == ENC 2 ------------------------------------------------
  elseif n == 2 then
    if view_key_count > 0 then
      if (grid_view_name == 'Chord' or grid_view_name == 'Arp') then -- Chord/Arp
        rotate_pattern(grid_view_name, d)
        grid_redraw()
      end
    elseif screen_view_name == 'Events' then
      -- Scroll through the Events menus (name, type, val)
      automator_events_index = util.clamp(automator_events_index + d, 1, #automator_events_menus)
      selected_automator_events_menu = automator_events_menus[automator_events_index]
    else
      menu_index = util.clamp(menu_index + d, 0, #menus[page_index])
      selected_menu = menus[page_index][menu_index]
    end

    -- n == ENC 3 -------------------------------------------------------------
  else
    if view_key_count > 0 then
      if (grid_view_name == 'Chord' or grid_view_name == 'Arp') then -- Chord/Arp
        transpose_pattern(grid_view_name, d)
        grid_redraw()
      end

      -- Change event value
    elseif screen_view_name == 'Events' then
      if selected_automator_events_menu == 'event_category' then
        params:delta(selected_automator_events_menu, d)
        set_event_category_min_max()
        -- Change event_name to first item in the selected Category and event_value to the current value (Set) or 0 (Increment)
        params:set('event_name', event_category_min_index)
        event_name = events_lookup[params:get('event_name')].id
        set_event_range()
        init_event_value()
      elseif selected_automator_events_menu == 'event_name' then
        local prev_event_name = event_name
        params:set(selected_automator_events_menu,
          util.clamp(params:get(selected_automator_events_menu) + d, event_category_min_index, event_category_max_index))
        event_name = events_lookup[params:get('event_name')].id
        -- We don't want values to be reset if user hits the start/end of the event_name range and keeps turning the encoder.
        if event_name ~= prev_event_name then
          set_event_range()
          init_event_value()
        end
      elseif selected_automator_events_menu == 'event_value_type' then
        local prev_event_value_str = params:string('event_value_type')
        params:delta(selected_automator_events_menu, d)
        set_event_range()
        if params:string('event_value_type') == 'Increment' and prev_event_value_str ~= 'Increment' then
          params:set('event_value', 0)
        elseif params:string('event_value_type') == 'Set' and prev_event_value_str ~= 'Set' then
          params:set('event_value', params:get(event_name))
        end

        -- Clamp the current event_value in case it's out-of-bounds
        params:set('event_value', util.clamp(params:get('event_value'), event_range[1], event_range[2]))
      elseif selected_automator_events_menu == 'event_value' then
        set_event_range()
        params:set('event_value',
          util.clamp(util.clamp(params:get('event_value'), event_range[1], event_range[2]) + d, event_range[1],
            event_range[2]))

        -- All other Events menus get the usual delta
      else
        params:delta(selected_automator_events_menu, d)
      end

      -- moving from arranger keys 1-4 to the arranger loop strip on row 5. This still trips me up but avoids weirdness around handling dual-use keypress (enable/disable vs. entering event editor)
    elseif grid_view_name == 'Arranger' and arranger_loop_key_count > 0 then
      -- Arranger segment detail options are on-screen
      if arranger_loop_key_count > 0 then -- redundant?
        d_cuml = d_cuml + d
        arranger_seq_length = util.clamp(arranger_seq_length_og + d_cuml, 1, max_arranger_seq_length)

        -- Shifting pattern to the right and opening up blank(s)
        if d > 0 then
          local d = 1                               -- Addresses some weirdness if encoder delta is more than 1 increment that I don't want to troubleshoot LOL
          for i = max_arranger_seq_length, 1, -1 do -- Process in reverse
            if i >= event_edit_pattern_og + d_cuml then
              arranger_seq[i] = arranger_seq_og[i - d_cuml]
              automator_events[i] = deepcopy(automator_events_og[i - d_cuml])
            elseif i >= event_edit_pattern_og and i < event_edit_pattern_og + d_cuml then
              arranger_seq[i] = 0
              for s = 1, 8 do -- To-do: hardcoded number of steps will eventually be extended
                automator_events[i][s] = {}
                automator_events[i].populated = nil
              end
            elseif i < event_edit_pattern_og then
              arranger_seq[i] = arranger_seq_og[i]
              automator_events[i] = deepcopy(automator_events_og[i])
            end
          end
          -- Shifting pattern to the left and overwriting existing patterns
        elseif d < 0 then
          local d = -1 -- Addresses some weirdness if encoder delta is more than 1 increment that I don't want to troubleshoot LOL
          for i = 1, max_arranger_seq_length do
            -- if arranger column is >= the newly-shifted pattern, shift over arranger_seq and automator_events.
            -- if the shift exceeds what is in automator_events_og, it will deepcopy over nothing which kinda breaks stuff
            if i >= event_edit_pattern_og + d_cuml then
              arranger_seq[i] = arranger_seq_og[i - d_cuml]
              automator_events[i] = deepcopy(automator_events_og[i - d_cuml])
            end

            -- 2023-04-11 adding something to pad out blank automator_events after deep copy since redraw+others break if missing
            if automator_events[i] == nil then
              automator_events[i] = {}
              for step = 1, 8 do -- needs to be expanded eventually for more than 8 steps
                automator_events[i][step] = {}
              end
            end
          end
        end
        generate_arranger_seq_padded()
        grid_redraw()
      end
    elseif screen_view_name == 'Session' then
      if menu_index == 0 then
        menu_index = 0
        page_index = util.clamp(page_index + d, 1, #pages)
        page_name = pages[page_index]
        selected_menu = menus[page_index][menu_index]
      else
        params:delta(selected_menu, d)
      end
    end
  end
  redraw()
end

function init_event_value()
  -- debuggin'
  -- print('init_event_value() called')
  -- print('event_name = ' .. event_name)
  -- print('event_type = ' ..events_lookup[params:get('event_name')].event_type)
  -- print('value_type mapping = ' .. events_lookup[params:get('event_name')].value_type)
  -- print('event_value_type = ' .. params:string('event_value_type'))

  if events_lookup[params:get('event_name')].event_type == 'param' then
    if (events_lookup[params:get('event_name')].value_type == 'inc, set' and params:string('event_value_type') == 'Set')
        or events_lookup[params:get('event_name')].value_type == 'set' then
      params:set('event_value', params:get(event_name))
    else
      params:set('event_value', 0)
    end
  else
    params:set('event_value', 0)
  end
end

function deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

function set_event_range()
  -- Determine if event range should be clamped
  if events_lookup[params:get('event_name')].event_type == 'param' then
    -- Unrestrict range if it's a param of the 'inc, set' type and is set to 'Increment'
    if events_lookup[params:get('event_name')].value_type == 'inc, set' and params:string('event_value_type') == 'Increment' then
      event_range = { -999, 999 }
    else -- 'Set', 'Trigger', etc...
      event_range = params:get_range(params.lookup[event_name]) or { -999, 999 }
    end
  else -- function. May have hardcoded ranges in events_lookup at some point
    event_range = { -999, 999 }
  end
end

function chord_steps_to_seconds(steps)
  return (steps * 60 / params:get('clock_tempo') / global_clock_div * chord_div) -- switched to var Fix: timing
end

-- -- Truncates hours. Requires integer.
-- function s_to_min_sec(s)
--   local m = math.floor(s/60)
--   -- local h = math.floor(m/60)
--   m = m%60
--   s = s%60
--   return string.format("%02d",m) ..":".. string.format("%02d",s)
-- end


-- Alternative for more digits up to 9 hours LETSGOOOOOOO
function s_to_min_sec(seconds)
  local seconds = tonumber(seconds)
  -- hours = (string.format("%02.f", math.floor(seconds/3600));
  hours_raw = math.floor(seconds / 3600);
  hours = string.format("%1.f", hours_raw);
  mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)));
  secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60));
  -- Modify hours if it's 2+ digits
  -- hours = hours < 10 and string.format("%2.f",hours) or '>';
  if hours_raw < 10 then
    return hours .. ":" .. mins .. ":" .. secs
  else
    return hours .. " hrs"
  end
end

function param_formatter(param)
  if param == 'source' then
    return ('Clock:')
  elseif param == 'midi out' then
    return ('Out:')
  else
    return (param .. ':')
  end
end

--index of list, count of items in list, #viewable, line height
function scroll_offset(index, total, in_view, height)
  if total > in_view and menu_index > 1 then
    --math.ceil might make jumps larger than necessary, but ensures nothing is cut off at the bottom of the menu
    return (math.ceil(((index - 1) * (total - in_view) * height / total)))
  else
    return (0)
  end
end

function redraw()
  screen.clear()
  local dash_x = 94

  -- Screens that pop up when g.keys are being held down take priority--------

  -- POP-up g.key tip always takes priority
  if view_key_count > 0 then
    -- screen.level(7)
    -- screen.move(64,32)
    -- screen.font_size(16)
    -- screen.text_center(grid_view_name)
    -- screen.font_size(8)

    if screen_view_name == 'Chord+arp' then
      screen.level(15)
      screen.move(2, 8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2, 28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2, 38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1, 54)
      screen.line(128, 54)
      screen.stroke()
      screen.level(3)
      screen.move(128, 62)
      screen.text_right('(K3) GEN. CHORDS+ARP')
    elseif grid_view_name == 'Arranger' then
      screen.level(15)
      screen.move(2, 8)
      -- Placeholder
      -- screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.text(string.upper(grid_view_name) .. ' GRID')
      -- screen.move(2,28)
      -- screen.text('ENC 2: Rotate seq ↑↓')
      -- screen.move(2,38)
      -- screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1, 54)
      screen.line(128, 54)
      screen.stroke()
      screen.level(3)

      -- The following key options were moved to arranger grid buttons
      -- screen.move(1,62)
      -- if params:get('arranger_enabled') == 0 then
      --   screen.text('(K2) ENABLE')
      -- else
      --   screen.text('(K2) DISABLE')
      -- end
      -- screen.move(128,62)
      -- if params:get('playback') == 1 then
      --   screen.text_right('(K3) ONE-SHOT')
      -- else
      --   screen.text_right('(K3) LOOP')
      -- end
    elseif grid_view_name == 'Chord' then --or grid_view_name == 'Arp') then-- Chord/Arp
      screen.level(15)
      screen.move(2, 8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2, 28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2, 38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1, 54)
      screen.line(128, 54)
      screen.stroke()
      screen.level(3)
      screen.move(128, 62)
      screen.text_right('(K3) GEN. CHORDS')
    elseif grid_view_name == 'Arp' then --or grid_view_name == 'Arp') then-- Chord/Arp
      screen.level(15)
      screen.move(2, 8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2, 28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2, 38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1, 54)
      screen.line(128, 54)
      screen.stroke()
      screen.level(3)
      screen.move(128, 62)
      screen.text_right('(K3) GEN. ARP')
    end

    -- Events editor intro
  elseif arranger_loop_key_count > 0 then
    screen.level(15)
    screen.move(2, 8)
    screen.text('Arranger segment ' .. event_edit_pattern)
    -- To-do: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2, 28)
    screen.text('ENC 3: Shift pattern ←→')
    screen.level(4)
    screen.move(1, 54)
    screen.line(128, 54)
    screen.stroke()
    screen.level(3)
    screen.move(1, 62)
    screen.text('(K2) JUMP TO')
    screen.move(82, 62)
    screen.text('(K3) EVENTS')

    -- Standard priority (not momentary) menus---------------------------------
  else
    ---------------------------
    -- UI elements placed here will persist in all views including Events editor
    ---------------------------

    ----------------
    -- Events screen
    ----------------
    if screen_view_name == 'Events' then
      screen.level(4)
      screen.move(2, 8)
      if event_edit_active == false then
        screen.text('Editing segment ' .. event_edit_pattern)
        screen.move(2, 28)
        screen.level(15)
        screen.text('Use Grid to select step (↑↓)')
        screen.move(2, 38)
        screen.text('and event number (←→)')
        screen.level(4)
        screen.move(1, 54)
        screen.line(128, 54)
        screen.stroke()
        screen.level(3)
        screen.move(1, 62)
        screen.text('(K2) DELETE ALL')
        screen.move(128, 62)
        screen.text_right('(K3) DONE')
      else
        -- Events sticky header
        screen.level(4)
        screen.rect(0, 0, 128, 11)
        screen.fill()
        screen.move(2, 8)
        screen.level(0)
        screen.text('SEGMENT ' .. event_edit_pattern .. '.' .. event_edit_step)
        screen.move(126, 8)
        screen.text_right('EVENT ' .. event_edit_lane .. '/16')

        -- Scrolling events menu
        local menu_offset = scroll_offset(automator_events_index, #automator_events_menus, 5, 10)
        line = 1
        for i = 1, #automator_events_menus do
          screen.move(2, line * 10 + 8 - menu_offset)
          screen.level(automator_events_index == i and 15 or 3)

          -- Switch between number and formatted value for Incremental and Set, respectively
          event_val_string = params:string(automator_events_menus[i])
          if automator_events_menus[i] == 'event_value' then
            if not (events_lookup[params:get('event_name')].value_type == 'inc, set' and params:string('event_value_type') == 'Increment') then
              if events_lookup[params:get('event_name')].formatter ~= nil then
                event_val_string = _G[events_lookup[params:get('event_name')].formatter](params:string('event_value'))
              elseif events_lookup[params:get('event_name')].event_type == 'param' and params:t(events_lookup[params:get('event_name')].id) == 2 then
                local options = params.params[params.lookup[events_lookup[params:get('event_name')].id]]
                    .options -- Make Local.
                event_val_string = options[params:get(automator_events_menus[i])]
              end
            end
          end

          -- Draw menu and <> indicators for scroll range
          -- Leaving in param formatter and some code for truncating string in case we want to eventually add system param events that require formatting.
          local events_menu_trunc = 22 -- WAG Un-local if limiting using the text_extents approach below
          if automator_events_index == i then
            local selected_events_menu = automator_events_menus[i]
            local range =
                (selected_events_menu == 'event_category' or selected_events_menu == 'event_value_type') and
                params:get_range(selected_events_menu)
                or selected_events_menu == 'event_name' and { event_category_min_index, event_category_max_index }
                or event_range
            local menu_value_suf = params:get(selected_events_menu) == range[1] and '>' or ''
            local menu_value_pre = params:get(selected_events_menu) == range[2] and '<' or ' '
            local events_menu_txt = first_to_upper(param_formatter(param_id_to_name(automator_events_menus[i]))) ..
                menu_value_pre .. string.sub(event_val_string, 1, events_menu_trunc) .. menu_value_suf
            screen.text(events_menu_txt)
          else
            screen.text(first_to_upper(param_formatter(param_id_to_name(automator_events_menus[i]))) ..
              ' ' .. string.sub(event_val_string, 1, events_menu_trunc))
          end

          line = line + 1
        end

        screen.level(4)
        screen.move(1, 54)
        screen.line(128, 54)
        screen.stroke()
        screen.level(3)
        screen.move(1, 62)
        screen.text('(K2) DELETE')
        screen.move(128, 62)
        screen.text_right('(K3) SAVE')
      end


      -- SESSION VIEW (NON-EVENTS), not holding down Arranger segments g.keys
    else
      ---------------------------
      -- UI elements placed here appear in all non-Events views
      ---------------------------

      --------------------------------------------
      -- Transport state, pattern, chord readout
      --------------------------------------------

      screen.level(9)
      screen.rect(dash_x + 1, 11, 33, 12)
      screen.stroke()

      screen.level(menu_index == 0 and 15 or 13)
      screen.rect(dash_x, 0, 34, 11)
      screen.fill()

      -- STATE determination. To-do: move this out of Redraw
      if arranger_seq_position == 0 and chord_seq_position == 0 then
        state = 5                                                    --stopped/reset
      else
        state = transport_active == true and stop ~= true and 4 or 3 --play or pause
      end

      -- Draw transport status glyph
      screen.level(0)
      local x_offset = dash_x + 26
      local y_offset = 3
      for i = 1, #glyphs[state] do
        screen.pixel(glyphs[state][i][1] + x_offset, glyphs[state][i][2] + y_offset)
      end
      screen.fill()

      --------------------------------------------
      -- Pattern position readout
      --------------------------------------------
      screen.move(dash_x + 3, y_offset + 5)
      screen.text(pattern_name[pattern] .. '.' .. chord_seq_position)

      --------------------------------------------
      -- Chord readout
      --------------------------------------------
      screen.level(15)
      if chord_no > 0 then
        screen.move(dash_x + 17, y_offset + 16)
        screen.text_center((chord_name or '') .. (chord_name_modifier or '')) -- Chord name. To-do: param to switch between this and chord_degree ?
      end

      --------------------------------------------
      -- Arranger dash
      --------------------------------------------
      local arranger_dash_y = 24

      -- Axis reference marks
      for i = 1, 4 do
        screen.level(1)
        screen.rect(dash_x + 3, arranger_dash_y + 12 + i * 3, 1, 2)
      end
      screen.pixel(dash_x + 3, arranger_dash_y + 27)
      screen.fill()

      -- Calculations for 1. ARRANGEMENT TIMER and 2. ARRANGER MINI CHART
      local rect_x = dash_x +
          (arranger_seq_position == 0 and 4 or 2) -- If arranger is reset, add an initial gap to the x position
      local events_rect_x = rect_x
      steps_remaining_in_arrangement = 0      -- Reset this before getting a running sum from the DO below

      for i = math.max(arranger_seq_position, 1), arranger_seq_length do
        if arranger_enabled then
          steps_elapsed = (i == arranger_seq_position and math.max(chord_seq_position - 1, 0) or 0) or 0
          percent_step_elapsed = arranger_seq_position == 0 and 0 or
          (math.max(clock_step, 0) % chord_div / (chord_div - 1))
        else
          -- Uses readout_chord_seq_position which is updated when chord advances and arranger_enabled == true
          steps_elapsed = (i == arranger_seq_position and math.max(readout_chord_seq_position - 1, 0) or 0) or 0
        end

        -- This is used as a replacement for arranger_seq_padded[i] in several places to handle situations where the chord pattern is changed unexpectedly:
        -- 1. User changes the current arranger segment pattern while on that segment. In this case we want to keep displaying the currently *playing* chord pattern
        -- 2. User changes the current chord pattern by double tapping it on the Chord grid view. This sets arranger_enabled to false and should suspend the arranger mini chart until Arranger pickup occurs.
        -- 3. Current arranger segment is turned off, resulting in it picking up a different pattern (either the previous pattern or wrapping around to grab the last pattern. arranger_seq_padded shenanigans)
        local pattern_stable = (arranger_seq_position == i and arranger_enabled == true) and pattern or
            arranger_seq_padded[i]

        -- Min of 0 since changing the number of pattern steps mid-play can otherwise result in a negative (possibly obsolete now?)
        steps_remaining_in_pattern = math.max(pattern_length[pattern_stable] - steps_elapsed, 0) --rect_w
        steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
        seconds_remaining_in_arrangement = chord_steps_to_seconds(steps_remaining_in_arrangement - percent_step_elapsed)

        local rect_y = arranger_dash_y + (pattern_stable * 2) + pattern_stable

        -- Cosmetic adjustment to gap if arranger_seq_position == 0 (reset)
        local rect_gap_adj = arranger_seq_position == 0 and 0 or arranger_seq_position - 1

        -- Automator event indicator. To-do: This is simpler than the above and can probably be used to draw the primary chart too.
        for s = i == arranger_seq_position and readout_chord_seq_position or 1, pattern_length[pattern_stable] do
          if params:get('arranger_enabled') == 1 then
            -- Dim the interrupted segment upon resume
            if arranger_enabled == false and i == arranger_seq_position then
              screen.level(((automator_events[i].populated or 0) > 0 and (automator_events[i][s].populated or 0) > 0) and
                4 or 1)
            else
              screen.level(((automator_events[i].populated or 0) > 0 and (automator_events[i][s].populated or 0) > 0) and
                15 or 1)
            end
          else
            screen.level(((automator_events[i].populated or 0) > 0 and (automator_events[i][s].populated or 0) > 0) and 4 or
              1)
          end

          screen.pixel(events_rect_x + i - rect_gap_adj, arranger_dash_y + 27, 1, 1)
          screen.fill()
          events_rect_x = events_rect_x + 1
        end

        -- Dim interrupted segment if Arranger is re-syncing
        if params:get('arranger_enabled') == 1 then
          screen.level(arranger_enabled == false and i == arranger_seq_position and 2 or 15)
        else
          screen.level(2)
        end
        screen.rect(rect_x + i - rect_gap_adj, rect_y + 12, steps_remaining_in_pattern, 2)
        screen.fill()

        rect_x = rect_x + steps_remaining_in_pattern
      end

      -- Arranger dash rect (rendered after chart to cover chart edge overlap)
      screen.level(params:get('arranger_enabled') == 1 and 9 or 2)

      screen.rect(dash_x + 1, arranger_dash_y + 2, 33, 38)
      screen.stroke()

      -- Header
      screen.level(params:get('arranger_enabled') == 1 and 10 or 2)
      screen.rect(dash_x, arranger_dash_y + 1, 34, 11)
      screen.fill()

      --------------------------------------------
      -- Arranger countdown timer readout
      --------------------------------------------

      -- Arranger time
      screen.level(params:get('arranger_enabled') == 1 and 15 or 3)

      -- Bottom left
      screen.move(dash_x + 3, arranger_dash_y + 36)
      screen.text(s_to_min_sec(math.ceil(seconds_remaining_in_arrangement)))

      -- Arranger mode glyph
      screen.level(0)
      local x_offset = dash_x + 26
      local y_offset = arranger_dash_y + 4
      if params:string('playback') == 'Loop' then
        for i = 1, #glyphs[1] do
          screen.pixel(glyphs[1][i][1] + x_offset, glyphs[1][i][2] + y_offset)
        end
      else
        for i = 1, #glyphs[2] do
          screen.pixel(glyphs[2][i][1] + x_offset, glyphs[2][i][2] + y_offset)
        end
      end

      --------------------------------------------
      -- Arranger position readout
      --------------------------------------------
      screen.move(dash_x + 3, arranger_dash_y + 9)
      if params:string('arranger_enabled') == 'True' and arranger_enabled == false then
        screen.text('T-' .. pattern_length[pattern] - chord_seq_position + 1)
      else
        screen.text(arranger_seq_position .. '.' .. readout_chord_seq_position)
      end

      screen.fill()

      --------------------------------------------
      -- Scrolling menus
      --------------------------------------------
      local menu_offset = scroll_offset(menu_index, #menus[page_index], 5, 10)
      line = 1
      for i = 1, #menus[page_index] do
        screen.move(2, line * 10 + 8 - menu_offset)
        screen.level(menu_index == i and 15 or 3)

        -- Generate menu and draw <> indicators for scroll range
        session_menu_trunc = 16
        if menu_index == i then
          local range = params:get_range(menus[page_index][i])
          local menu_value_suf = params:get(menus[page_index][i]) == range[1] and '>' or ''
          local menu_value_pre = params:get(menus[page_index][i]) == range[2] and '<' or ' '
          local session_menu_txt = first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) ..
              menu_value_pre .. string.sub(params:string(menus[page_index][i]), 1, session_menu_trunc) .. menu_value_suf

          while screen.text_extents(session_menu_txt) > 90 do
            session_menu_trunc = session_menu_trunc - 1
            session_menu_txt = first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) ..
                menu_value_pre ..
                string.sub(params:string(menus[page_index][i]), 1, session_menu_trunc) .. menu_value_suf
          end

          screen.text(session_menu_txt)
        else
          screen.text(first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) ..
            ' ' .. string.sub(params:string(menus[page_index][i]), 1, 16))
        end
        line = line + 1
      end

      --Sticky header
      screen.level(menu_index == 0 and 15 or 4)
      screen.rect(0, 0, 92, 11)
      screen.fill()
      screen.move(2, 8)
      screen.level(0)
      screen.text(page_name)
      screen.fill()
    end -- of event vs. non-event check
  end
  screen.update()
end
