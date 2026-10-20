-- Deck of Equilibrium, standalone port.
-- Original deck and shop logic: Cryptid (github.com/SpectralPack/Cryptid, lib/overrides.lua
-- and items/deck.lua), GPL-3.0. This port keeps the same behaviour without the rest of Cryptid:
-- every Joker, consumable, voucher, booster and playing card has the same chance to appear in
-- any shop slot, and the run starts with Overstock + Overstock Plus.

EQD = EQD or {}

SMODS.Atlas({ key = "deck", path = "eq_deck.png", px = 71, py = 95 })

SMODS.Back({
	key = "equilibrium",
	atlas = "deck",
	pos = { x = 0, y = 0 },
	config = { vouchers = { "v_overstock_norm", "v_overstock_plus" } },
	unlocked = true,
	discovered = true,
	loc_txt = {
		name = "Deck of Equilibrium",
		text = {
			"All cards have the",
			"{C:attention}same chance{} of",
			"appearing in shops,",
			"start run with",
			"{C:attention,T:v_overstock_plus}Overstock Plus",
		},
	},
	apply = function(self)
		G.GAME.modifiers.eqd_equilibrium = true
	end,
})

local function active()
	return G.GAME and G.GAME.modifiers and G.GAME.modifiers.eqd_equilibrium
end

function EQD.is_playing_card_center(center)
	return center and (center.set == "Default" or center.set == "Enhanced" or center.key == "c_base")
end

-- Equivalent of Cryptid.can_spawn_equilibrium. Also honours banned keys (Multiplayer rulesets
-- ban cards that way) and modded in_pool gates (Multiplayer layer-gated cards).
function EQD.can_spawn(center)
	if not center then return false end
	if center.unlocked == false and center.set ~= "Booster" then return false end
	if G.GAME.banned_keys and G.GAME.banned_keys[center.key] then return false end
	if center.no_doe then return false end
	-- Multiplayer gates its ruleset-specific cards (j_mp_*, c_mp_*) per active layer.
	if MP and MP.should_exclude_from_pool and MP.should_exclude_from_pool(center) then return false end
	if center.mod and type(center.in_pool) == "function" then
		local ok, res = pcall(center.in_pool, center, {})
		if ok and res == false then return false end
	end
	return true
end

-- Port of Cryptid.poll_equilibrium_key: one flat pool, equal weight per entry.
function EQD.poll_key(seed)
	seed = seed or "cry_equilibrium"
	local pool, all_unavailable = {}, true
	for _, id in ipairs({ "Joker", "Consumeables", "Voucher", "Booster", "Default" }) do
		if id == "Default" then
			if EQD.can_spawn(G.P_CENTERS.c_base) then
				for _ in pairs(G.P_CARDS) do
					pool[#pool + 1] = "c_base"
					all_unavailable = false
				end
			end
		elseif G.P_CENTER_POOLS[id] then
			for _, v in pairs(G.P_CENTER_POOLS[id]) do
				if EQD.can_spawn(v) then
					pool[#pool + 1] = v.key
					all_unavailable = false
				else
					pool[#pool + 1] = "UNAVAILABLE"
				end
			end
		end
	end
	if all_unavailable then return "j_joker", false end

	local res = pseudorandom_element(pool, pseudoseed(seed))
	local i = 1
	while res == "UNAVAILABLE" do
		res = pseudorandom_element(pool, pseudoseed(seed .. "_resample" .. i))
		i = i + 1
	end
	local pcard = false
	if res == "c_base" then
		pcard = true
		local new_p = { "c_base" }
		for _, v in ipairs(G.P_CENTER_POOLS.Enhanced) do
			if EQD.can_spawn(v) then new_p[#new_p + 1] = v.key end
		end
		res = pseudorandom_element(new_p, pseudoseed(seed .. "2"))
	end
	return res, pcard
end

local get_pack_ref = get_pack
function get_pack(_key, _type)
	if active() then return G.P_CENTERS[EQD.poll_key("cry_equipackbrium")] end
	return get_pack_ref(_key, _type)
end

local get_next_vouchers_ref = SMODS.get_next_vouchers
function SMODS.get_next_vouchers(vouchers)
	if not active() then return get_next_vouchers_ref(vouchers) end
	vouchers = vouchers or { spawn = {} }
	for _ = #vouchers + 1, G.GAME.starting_params.vouchers_in_shop + (G.GAME.modifiers.extra_vouchers or 0) do
		local key = EQD.poll_key("cry_equivoucherium") or "j_joker"
		vouchers[#vouchers + 1] = key
		vouchers.spawn[key] = true
	end
	return vouchers
end

local add_booster_ref = SMODS.add_booster_to_shop
function SMODS.add_booster_to_shop(key, ...)
	if not active() then return add_booster_ref(key, ...) end
	if key then assert(G.P_CENTERS[key], "Invalid booster key: " .. key) else key = get_pack("shop_pack").key end
	local center = G.P_CENTERS[key]
	local scale = center.set == "Booster" and 1.27 or 1
	local is_playing = EQD.is_playing_card_center(center)
	local front = is_playing and pseudorandom_element(G.P_CARDS, pseudoseed("cry_equifrontbrium")) or G.P_CARDS.empty
	local card = Card(G.shop_booster.T.x + G.shop_booster.T.w / 2, G.shop_booster.T.y,
		G.CARD_W * scale, G.CARD_H * scale, front, center,
		{ bypass_discovery_center = true, bypass_discovery_ui = true })
	create_shop_card_ui(card, is_playing and "Base" or center.set, G.shop_booster)
	card.ability.booster_pos = #G.shop_booster.cards + 1
	card:start_materialize()
	G.shop_booster:emplace(card)
	return card
end

local add_voucher_ref = SMODS.add_voucher_to_shop
function SMODS.add_voucher_to_shop(key, dont_save, ...)
	if not active() then return add_voucher_ref(key, dont_save, ...) end
	if key then
		assert(G.P_CENTERS[key], "Invalid voucher key: " .. key)
	else
		key = get_next_voucher_key()
		if not dont_save then
			G.GAME.current_round.voucher.spawn[key] = true
			G.GAME.current_round.voucher[#G.GAME.current_round.voucher + 1] = key
		end
	end
	local center = G.P_CENTERS[key]
	local is_playing = EQD.is_playing_card_center(center)
	local front = is_playing and pseudorandom_element(G.P_CARDS,
		pseudoseed("cry_equifrontbrium" .. (G.GAME.round_resets.ante or 1) .. key)) or G.P_CARDS.empty
	local card = Card(G.shop_vouchers.T.x + G.shop_vouchers.T.w / 2, G.shop_vouchers.T.y,
		G.CARD_W, G.CARD_H, front, center, { bypass_discovery_center = true, bypass_discovery_ui = true })
	card.shop_voucher = true
	create_shop_card_ui(card, is_playing and "Base" or center.set, G.shop_vouchers)
	card:start_materialize()
	G.shop_vouchers:emplace(card)
	G.shop_vouchers.config.card_limit = #G.shop_vouchers.cards
	return card
end

local create_card_for_shop_ref = create_card_for_shop
function create_card_for_shop(area)
	if not (active() and area == G.shop_jokers) then return create_card_for_shop_ref(area) end

	-- Tags that force a shop card (e.g. Uncommon/Rare/Foil tags) still apply first.
	for _, tag in ipairs(G.GAME.tags) do
		local forced = tag:apply_to_run({ type = "store_joker_create", area = area })
		if forced then
			for _, t2 in ipairs(G.GAME.tags) do
				if t2:apply_to_run({ type = "store_joker_modify", card = forced }) then break end
			end
			return forced
		end
	end

	local key, pcard = EQD.poll_key("cry_equilibrium")
	local center = G.P_CENTERS[key]
	local set, create_set, enhancement = center.set, center.set, nil
	if center.set == "Default" or center.key == "c_base" then
		create_set = "Base"
	elseif center.set == "Enhanced" then
		create_set = "Enhanced"
		enhancement = center.key
	end
	local args = {
		set = create_set,
		area = area,
		key_append = "sho",
		front = pcard and pseudorandom_element(G.P_CARDS, pseudoseed("cry_equifrontbrium")) or nil,
		key = not enhancement and (create_set == "Base" and "c_base" or center.key) or nil,
		enhancement = enhancement,
		edition = pcard and poll_edition("cry_equiplaying_edition" .. G.GAME.round_resets.ante, 2, true) or nil,
		seal = pcard and SMODS.poll_seal({ mod = 10 }) or nil,
		silent = true,
	}
	local flags = SMODS.calculate_context({ create_shop_card = true, set = create_set, cardarea = area })
	local card = SMODS.create_card(SMODS.merge_defaults(flags.shop_create_flags or {}, args))
	SMODS.calculate_context({ modify_shop_card = true, card = card })
	create_shop_card_ui(card, set, area)
	G.E_MANAGER:add_event(Event({
		func = function()
			for _, tag in ipairs(G.GAME.tags) do
				if tag:apply_to_run({ type = "store_joker_modify", card = card }) then break end
			end
			return true
		end,
	}))
	return card
end
