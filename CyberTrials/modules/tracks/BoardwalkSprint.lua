local raceLogic = require("modules/utils/raceLogic")

--Observes
    ObserveAfter('NPCDeathListener', 'SendPotentialDeathEvent', function(self, event)
        if not raceLogic.raceInProgress then return end
        if raceLogic.track.name == "Boardwalk Sprint" then
            BoardwalkSprint.hasHit = false
            BoardwalkSprint.killcount = BoardwalkSprint.killcount + 1
            Game.AddToInventory('Items.money', 250)
        end
    end)

    Observe('VehicleObject', 'ReactToHitProcess', function(self, event)
        if not raceLogic.raceInProgress then return end
        if raceLogic.track.name == "Boardwalk Sprint" then
            if BoardwalkSprint.hasHit == false then
                BoardwalkSprint.hasHit = true
            end
        end
    end)
--End Observes

BoardwalkSprint = {
    killcount = 0,
    hasHit = false,
    hasCustomWindow = true,
    cetopen = false,
    name = "Boardwalk Sprint",
    description = "Sprint race along the beach in Pacifica - - - Created By: TheManualEnahcer",
    creator = "TheManualEnahcer",
    numberOfLaps = 1,
    hubPosition = {
        position = { x = -2835.3198242188, y = -2667.0278320313, z = 23.147438049316 },
        rotation = { roll = 0, pitch = 0, yaw = -18.669916152954 }
    },
    startPosition = {
        position = { x = -2844.5087890625, y = -2665.9946289063, z = 22.714866638184 },
        rotation = { roll = 0, pitch = 0, yaw = 25.380109786987 }
    },
    checkpoints = {
        {position = { x = -2869.7009277344, y = -2607.0893554688, z = 18.344068527222 }, rotation = { roll = 0, pitch = 0, yaw = 21.423383712769 }},
        {position = { x = -2898.3537597656, y = -2547.0139160156, z = 14.459257125854 }, rotation = { roll = 0, pitch = 0, yaw = -11.729271888733 }},
        {position = { x = -2879.7062988281, y = -2467.4089355469, z = 7.2446279525757 }, rotation = { roll = 0, pitch = 0, yaw = 9.5021820068359 }},
        {position = { x = -2817.1889648438, y = -2385.19921875, z = 8.3535842895508 }, rotation = { roll = 0, pitch = 0, yaw = -62.272243499756 }},
        {position = { x = -2768.4536132813, y = -2367.7631835938, z = 8.0715827941895 }, rotation = { roll = 0, pitch = 0, yaw = -89.858192443848 }},
        {position = { x = -2683.3149414063, y = -2391.0068359375, z = 4.9173135757446 }, rotation = { roll = 0, pitch = 0, yaw = -124.53748321533 }},
        {position = { x = -2617.3649902344, y = -2362.6845703125, z = 6.7226510047913 }, rotation = { roll = 0, pitch = 0, yaw = -62.173179626465 }},
        {position = { x = -2543.646484375, y = -2334.2016601563, z = 8.3849611282349 }, rotation = { roll = 0, pitch = 0, yaw = -85.916641235352 }},
        {position = { x = -2432.7412109375, y = -2313.5817871094, z = 10.321022033691 }, rotation = { roll = 0, pitch = 0, yaw = -80.301620483398 }},
        {position = { x = -2396.5122070313, y = -2324.2492675781, z = 10.459285736084 }, rotation = { roll = 0, pitch = 0, yaw = -99.414756774902 }},
        {position = { x = -2373.6770019531, y = -2311.9567871094, z = 11.865948677063 }, rotation = { roll = 0, pitch = 0, yaw = -37.444709777832 }},
        {position = { x = -2377.0737304688, y = -2274.8015136719, z = 11.233695983887 }, rotation = { roll = 0, pitch = 0, yaw = 0.33866849541664 }},
        {position = { x = -2363.392578125, y = -2222.3862304688, z = 11.319370269775 }, rotation = { roll = 0, pitch = 0, yaw = -53.110942840576 }},
        {position = { x = -2300.2106933594, y = -2173.6672363281, z = 11.644690513611 }, rotation = { roll = 0, pitch = 0, yaw = -46.313972473145 }},
        {position = { x = -2243.724609375, y = -2124.5329589844, z = 11.634826660156 }, rotation = { roll = 0, pitch = 0, yaw = -49.418262481689 }},
        {position = { x = -2180.8195800781, y = -2058.9631347656, z = 11.786293029785 }, rotation = { roll = 0, pitch = 0, yaw = -6.2199692726135 }},
        {position = { x = -2191.5793457031, y = -2035.6201171875, z = 11.394788742065 }, rotation = { roll = 0, pitch = 0, yaw = 43.484893798828 }},
        {position = { x = -2220.2971191406, y = -1997.9038085938, z = 6.2250308990479 }, rotation = { roll = 0, pitch = 0, yaw = 3.9283955097198 }},
        {position = { x = -2182.2231445313, y = -1954.9272460938, z = 6.1260991096497 }, rotation = { roll = 0, pitch = 0, yaw = -17.797822952271 }},
        {position = { x = -2186.11328125, y = -1934.9747314453, z = 6.093505859375 }, rotation = { roll = 0, pitch = 0, yaw = -17.354686737061 }},
        {position = { x = -2165.4582519531, y = -1911.1785888672, z = 6.4634418487549 }, rotation = { roll = 0, pitch = 0, yaw = -69.423866271973 }},
        {position = { x = -2107.2470703125, y = -1889.1940917969, z = 5.9969773292542 }, rotation = { roll = 0, pitch = 0, yaw = -59.178188323975 }},
        {position = { x = -2044.2200927734, y = -1830.7932128906, z = 4.8131370544434 }, rotation = { roll = 0, pitch = 0, yaw = -29.129367828369 }},
        {position = { x = -1982.2840576172, y = -1749.6531982422, z = 4.9402933120728 }, rotation = { roll = 0, pitch = 0, yaw = -44.006580352783 }},
        {position = { x = -1952.2849121094, y = -1721.9260253906, z = 5.1183519363403 }, rotation = { roll = 0, pitch = 0, yaw = -22.578586578369 }},
        {position = { x = -1945.9077148438, y = -1674.4432373047, z = 5.6440539360046 }, rotation = { roll = 0, pitch = 0, yaw = -9.9186944961548 }},
        {position = { x = -1930.4898681641, y = -1616.1936035156, z = 6.002290725708 }, rotation = { roll = 0, pitch = 0, yaw = -23.712211608887 }},
        {position = { x = -1905.9486083984, y = -1572.1447753906, z = 4.7474155426025 }, rotation = { roll = 0, pitch = 0, yaw = -61.840869903564 }},
        {position = { x = -1878.8176269531, y = -1556.5207519531, z = 8.0978555679321 }, rotation = { roll = 0, pitch = 0, yaw = -65.289436340332 }},
        {position = { x = -1868.8546142578, y = -1557.12890625, z = 9.9759769439697 }, rotation = { roll = 0, pitch = 0, yaw = -102.4817276001 }},
        {position = { x = -1861.4013671875, y = -1572.0583496094, z = 11.718090057373 }, rotation = { roll = 0, pitch = 0, yaw = -147.70315551758 }},
        {position = { x = -1853.4937744141, y = -1576.4951171875, z = 13.226441383362 }, rotation = { roll = 0, pitch = 0, yaw = -64.40315246582 }},
        {position = { x = -1840.7502441406, y = -1563.8099365234, z = 16.143644332886 }, rotation = { roll = 0, pitch = 0, yaw = -51.841968536377 }},
        {position = { x = -1828.7897949219, y = -1563.5872802734, z = 17.248889923096 }, rotation = { roll = 0, pitch = 0, yaw = -163.31874084473 }},
        {position = { x = -1835.0368652344, y = -1600.4831542969, z = 18.129884719849 }, rotation = { roll = 0, pitch = 0, yaw = 147.22152709961 }},
    },
    checkpointEnts = {
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_finish.ent",
    },
    totalCheckpoints = 35,
    props = {
        {position = { x = -2425.6704101563, y = -2301.9494628906, z = 10.277323722839 }, rotation = { roll = 0, pitch = 0, yaw = 170.54135131836 }},
        {position = { x = -2429.2297363281, y = -2302.2106933594, z = 10.271329879761 }, rotation = { roll = 0, pitch = 0, yaw = -174.70861816406 }},
        {position = { x = -2433.0861816406, y = -2303.1096191406, z = 10.173534393311 }, rotation = { roll = 0, pitch = 0, yaw = -152.40863037109 }},
        {position = { x = -2429.4750976563, y = -2322.6364746094, z = 10.37133026123 }, rotation = { roll = 0, pitch = 0, yaw = 158.84133911133 }},
        {position = { x = -2434.19921875, y = -2321.3254394531, z = 10.358558654785 }, rotation = { roll = 0, pitch = 0, yaw = 166.14134216309 }},
        {position = { x = -2439.3693847656, y = -2321.1867675781, z = 10.344383239746 }, rotation = { roll = 0, pitch = 0, yaw = -174.20863342285 }},
        {position = { x = -2444.2990722656, y = -2322.6628417969, z = 10.358039855957 }, rotation = { roll = 0, pitch = 0, yaw = -169.25863647461 }},
        {position = { x = -2449.5808105469, y = -2322.6047363281, z = 10.79125213623 }, rotation = { roll = 0, pitch = 0, yaw = -171.1586151123 }},
        {position = { x = -2413.2868652344, y = -2321.08203125, z = 10.525610923767 }, rotation = { roll = 0, pitch = 0, yaw = -158.55865478516 }},
        {position = { x = -2413.9267578125, y = -2322.728515625, z = 10.525820732117 }, rotation = { roll = 0, pitch = 0, yaw = -69.208633422852 }},
        {position = { x = -2412.2844238281, y = -2323.3544921875, z = 10.526151657104 }, rotation = { roll = 0, pitch = 0, yaw = 23.791334152222 }},
        {position = { x = -2422.7072753906, y = -2324.9196777344, z = 10.652161598206 }, rotation = { roll = 0, pitch = 0, yaw = -156.15866088867 }},
        {position = { x = -2423.375, y = -2326.5397949219, z = 10.652286529541 }, rotation = { roll = 0, pitch = 0, yaw = -63.508644104004 }},
        {position = { x = -2430.611328125, y = -2323.1677246094, z = 10.363372802734 }, rotation = { roll = 0, pitch = 0, yaw = -19.85870552063 }},
        {position = { x = -2422.1018066406, y = -2302.7702636719, z = 10.297043800354 }, rotation = { roll = 0, pitch = 0, yaw = 145.49131774902 }},
        {position = { x = -2403.5454101563, y = -2315.1440429688, z = 10.448744773865 }, rotation = { roll = 0, pitch = 0, yaw = 145.34130859375 }},
        {position = { x = -2403.142578125, y = -2334.8999023438, z = 10.433439254761 }, rotation = { roll = 0, pitch = 0, yaw = 11.99133014679 }},
        {position = { x = -2415.88671875, y = -2333.8605957031, z = 10.458416938782 }, rotation = { roll = 0, pitch = 0, yaw = -16.108644485474 }},
        {position = { x = -2423.130859375, y = -2303.4763183594, z = 10.301683425903 }, rotation = { roll = 0, pitch = 0, yaw = -51.35863494873 }},
        {position = { x = -2421.1472167969, y = -2307.041015625, z = 10.342832565308 }, rotation = { roll = 0, pitch = 0, yaw = -60.60860824585 }},
        {position = { x = -2418.162109375, y = -2309.9897460938, z = 10.378502845764 }, rotation = { roll = 0, pitch = 0, yaw = -35.158599853516 }},
        {position = { x = -2414.6528320313, y = -2312.2355957031, z = 10.405676841736 }, rotation = { roll = 0, pitch = 0, yaw = -23.558557510376 }},
        {position = { x = -2411.4921875, y = -2313.3122558594, z = 10.419619560242 }, rotation = { roll = 0, pitch = 0, yaw = -18.908561706543 }},
        {position = { x = -2403.8701171875, y = -2317.0532226563, z = 10.453475952148 }, rotation = { roll = 0, pitch = 0, yaw = -35.558578491211 }},
        {position = { x = -2406.2905273438, y = -2315.2016601563, z = 10.444174766541 }, rotation = { roll = 0, pitch = 0, yaw = -40.758625030518 }},
        {position = { x = -2401.734375, y = -2331.63671875, z = 10.445595741272 }, rotation = { roll = 0, pitch = 0, yaw = -167.55863952637 }},
        {position = { x = -2406.0769042969, y = -2332.1984863281, z = 10.453243255615 }, rotation = { roll = 0, pitch = 0, yaw = -172.85864257813 }},
        {position = { x = -2410.7346191406, y = -2332.384765625, z = 10.457013130188 }, rotation = { roll = 0, pitch = 0, yaw = -176.35862731934 }},
        {position = { x = -2415.7531738281, y = -2332.2451171875, z = 10.460845947266 }, rotation = { roll = 0, pitch = 0, yaw = 179.94132995605 }},
        {position = { x = -2420.4890136719, y = -2331.0170898438, z = 10.465962409973 }, rotation = { roll = 0, pitch = 0, yaw = 157.64134216309 }},
        {position = { x = -2425.5539550781, y = -2324.3486328125, z = 10.427223205566 }, rotation = { roll = 0, pitch = 0, yaw = 151.49130249023 }},
        {position = { x = -2380.8923339844, y = -2330.6628417969, z = 10.391827583313 }, rotation = { roll = 0, pitch = 0, yaw = 19.341373443604 }},
        {position = { x = -2367.4331054688, y = -2325.736328125, z = 11.77779006958 }, rotation = { roll = 0, pitch = 0, yaw = -61.608612060547 }},
        {position = { x = -2380.8801269531, y = -2294.2644042969, z = 11.737228393555 }, rotation = { roll = 0, pitch = 0, yaw = -75.808631896973 }},
        {position = { x = -2388.1713867188, y = -2325.3032226563, z = 10.443762779236 }, rotation = { roll = 0, pitch = 0, yaw = 22.241380691528 }},
        {position = { x = -2381.5217285156, y = -2322.6267089844, z = 10.440714836121 }, rotation = { roll = 0, pitch = 0, yaw = 27.441390991211 }},
        {position = { x = -2376.2573242188, y = -2320.591796875, z = 10.437385559082 }, rotation = { roll = 0, pitch = 0, yaw = 23.441400527954 }},
        {position = { x = -2371.4885253906, y = -2318.0197753906, z = 11.839796066284 }, rotation = { roll = 0, pitch = 0, yaw = 41.091388702393 }},
        {position = { x = -2362.7175292969, y = -2303.1408691406, z = 11.864549636841 }, rotation = { roll = 0, pitch = 0, yaw = 68.541358947754 }},
        {position = { x = -2363.97265625, y = -2297.6162109375, z = 11.834806442261 }, rotation = { roll = 0, pitch = 0, yaw = -71.908683776855 }},
        {position = { x = -2366.099609375, y = -2292.0988769531, z = 11.768938064575 }, rotation = { roll = 0, pitch = 0, yaw = -75.758720397949 }},
        {position = { x = -2368.2585449219, y = -2286.7744140625, z = 11.67730140686 }, rotation = { roll = 0, pitch = 0, yaw = -74.958740234375 }},
        {position = { x = -2369.751953125, y = -2282.505859375, z = 11.591592788696 }, rotation = { roll = 0, pitch = 0, yaw = -79.45873260498 }},
        {position = { x = -2174.5241699219, y = -2065.8681640625, z = 11.98629283905 }, rotation = { roll = 0, pitch = 0, yaw = 6.7417726516724 }},
        {position = { x = -2164.1938476563, y = -2054.30859375, z = 11.986293792725 }, rotation = { roll = 0, pitch = 0, yaw = 135.79180908203 }},
        {position = { x = -2174.51171875, y = -2063.5783691406, z = 11.786293029785 }, rotation = { roll = 0, pitch = 0, yaw = -116.3581161499 }},
        {position = { x = -2169.6330566406, y = -2049.193359375, z = 11.986308097839 }, rotation = { roll = 0, pitch = 0, yaw = -89.508071899414 }},
        {position = { x = -2170.3603515625, y = -2043.2086181641, z = 11.986303329468 }, rotation = { roll = 0, pitch = 0, yaw = -78.358070373535 }},
        {position = { x = -2176.8334960938, y = -1943.7125244141, z = 7.4862203598022 }, rotation = { roll = 0, pitch = 0, yaw = 99.649887084961 }},
        {position = { x = -2179.0112304688, y = -1937.5499267578, z = 7.7148361206055 }, rotation = { roll = 0, pitch = 0, yaw = -64.150169372559 }},
        {position = { x = -2177.5463867188, y = -1940.3345947266, z = 7.5732092857361 }, rotation = { roll = 0, pitch = 0, yaw = -67.550163269043 }},
        {position = { x = -2178.1213378906, y = -1961.4658203125, z = 6.2474989891052 }, rotation = { roll = 0, pitch = 0, yaw = 82.449836730957 }},
        {position = { x = -2178.8359375, y = -1965.4113769531, z = 5.8637275695801 }, rotation = { roll = 0, pitch = 0, yaw = 86.499855041504 }},
        {position = { x = -2175.1872558594, y = -1944.1165771484, z = 7.5636148452759 }, rotation = { roll = 0, pitch = 0, yaw = 163.44981384277 }},
        {position = { x = -2193.9450683594, y = -1938.9901123047, z = 5.5775909423828 }, rotation = { roll = 0, pitch = 0, yaw = -33.050170898438 }},
        {position = { x = -2179.4306640625, y = -1926.1198730469, z = 5.7552490234375 }, rotation = { roll = 0, pitch = 0, yaw = 61.69987487793 }},
        {position = { x = -2195.44140625, y = -1931.3530273438, z = 5.4549255371094 }, rotation = { roll = 0, pitch = 0, yaw = 81.249961853027 }},
        {position = { x = -2194.6704101563, y = -1927.2401123047, z = 5.3466148376465 }, rotation = { roll = 0, pitch = 0, yaw = 76.55004119873 }},
        {position = { x = -2193.2106933594, y = -1922.7299804688, z = 5.4176964759827 }, rotation = { roll = 0, pitch = 0, yaw = 68.10001373291 }},
        {position = { x = -2190.2790527344, y = -1919.2099609375, z = 5.4910697937012 }, rotation = { roll = 0, pitch = 0, yaw = 33.30004119873 }},
        {position = { x = -2185.1662597656, y = -1916.1575927734, z = 5.6456680297852 }, rotation = { roll = 0, pitch = 0, yaw = 31.950038909912 }},
        {position = { x = -2179.5483398438, y = -1924.1292724609, z = 5.7439575195313 }, rotation = { roll = 0, pitch = 0, yaw = -139.94995117188 }},
        {position = { x = -2175.7565917969, y = -1922.810546875, z = 5.859402179718 }, rotation = { roll = 0, pitch = 0, yaw = -169.54989624023 }},
        {position = { x = -2145.0732421875, y = -1902.9971923828, z = 7.0476570129395 }, rotation = { roll = 0, pitch = 0, yaw = -179.09986877441 }},
        {position = { x = -2120.2746582031, y = -1904.95703125, z = 6.2412757873535 }, rotation = { roll = 0, pitch = 0, yaw = 31.250144958496 }},
        {position = { x = -2097.0881347656, y = -1876.4140625, z = 5.7553310394287 }, rotation = { roll = 0, pitch = 0, yaw = -145.79988098145 }},
        {position = { x = -2061.0310058594, y = -1864.9645996094, z = 5.6759643554688 }, rotation = { roll = 0, pitch = 0, yaw = 27.050178527832 }},
        {position = { x = -2051.236328125, y = -1837.5827636719, z = 4.8861389160156 }, rotation = { roll = 0, pitch = 0, yaw = -126.89984130859 }},
        {position = { x = -2029.4841308594, y = -1812.9830322266, z = 5.4183502197266 }, rotation = { roll = 0, pitch = 0, yaw = 62.750194549561 }},
        {position = { x = -2008.8354492188, y = -1772.7893066406, z = 5.3663396835327 }, rotation = { roll = 0, pitch = 0, yaw = -133.94976806641 }},
        {position = { x = -1965.3647460938, y = -1743.1182861328, z = 4.9377517700195 }, rotation = { roll = 0, pitch = 0, yaw = 33.800258636475 }},
        {position = { x = -1942.3098144531, y = -1699.3098144531, z = 5.8398056030273 }, rotation = { roll = 0, pitch = 0, yaw = 94.25023651123 }},
        {position = { x = -1943.5936279297, y = -1643.1507568359, z = 6.1011810302734 }, rotation = { roll = 0, pitch = 0, yaw = -106.99963378906 }},
        {position = { x = -1913.8521728516, y = -1576.1636962891, z = 4.7301025390625 }, rotation = { roll = 0, pitch = 0, yaw = -120.99964904785 }},
        {position = { x = -1870.4060058594, y = -1562.748046875, z = 10.085487365723 }, rotation = { roll = 0, pitch = 0, yaw = -19.549667358398 }},
        {position = { x = -1856.2672119141, y = -1571.6231689453, z = 12.389701843262 }, rotation = { roll = 0, pitch = 0, yaw = 140.90029907227 }},
        {position = { x = -1835.3681640625, y = -1567.1997070313, z = 16.671058654785 }, rotation = { roll = 0, pitch = 0, yaw = 19.200357437134 }},
        {position = { x = -1836.1663818359, y = -1590.9603271484, z = 17.933052062988 }, rotation = { roll = 0, pitch = 0, yaw = -85.599624633789 }},
        {position = { x = -1825.4899902344, y = -1585.8635253906, z = 17.524543762207 }, rotation = { roll = 0, pitch = 0, yaw = 102.55030059814 }},
        {position = { x = -1821.8806152344, y = -1565.6567382813, z = 17.060264587402 }, rotation = { roll = 0, pitch = 0, yaw = 110.45032501221 }},
        {position = { x = -1847.7547607422, y = -1580.6589355469, z = 14.413246154785 }, rotation = { roll = 0, pitch = 0, yaw = 37.05029296875 }},
        {position = { x = -1884.060546875, y = -1553.1801757813, z = 7.7503814697266 }, rotation = { roll = 0, pitch = 0, yaw = -162.09973144531 }},
    },
    propEnts = {
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
        "base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent",
    },
    totalProps = 82,
}

function BoardwalkSprint.init()
    BoardwalkSprint.killcount = 0
    BoardwalkSprint.hasHit = false
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, point in ipairs(BoardwalkSprint.checkpoints) do
        trans:SetPosition(ToVector4(point.position))
        trans:SetOrientation(ToEulerAngles(point.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(BoardwalkSprint.checkpointEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function BoardwalkSprint.spawnProps()
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, prop in ipairs(BoardwalkSprint.props) do
        trans:SetPosition(ToVector4(prop.position))
        trans:SetOrientation(ToEulerAngles(prop.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(BoardwalkSprint.propEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function BoardwalkSprint.GetCheckpointPositions()
    BoardwalkSprint.killcount = 0
    BoardwalkSprint.hasHit = false
    local val = {}
    for _, point in ipairs(BoardwalkSprint.checkpoints) do
        table.insert(val, ToVector4(point.position))
    end
    return val
end

function BoardwalkSprint.GetPropPositions()
    local propVal = {}
    for _, prop in ipairs(BoardwalkSprint.props) do
        table.insert(propVal, ToVector4(prop.position))
    end
    return propVal
end

function BoardwalkSprint.GetCheckpointRotations()
    local rotVal = {}
    for _, point in ipairs(BoardwalkSprint.checkpoints) do
        table.insert(rotVal, ToEulerAngles(point.rotation))
    end
    return rotVal
end

function BoardwalkSprint.GetPropRotations()
    local propRotVal = {}
    for _, prop in ipairs(BoardwalkSprint.props) do
        table.insert(propRotVal, ToEulerAngles(prop.rotation))
    end
    return propRotVal
end

function BoardwalkSprint.GetCheckpointEntities()
    local entVal = {}
    for _, path in ipairs(BoardwalkSprint.checkpointEnts) do
        table.insert(entVal, path)
    end
    return entVal
end

function BoardwalkSprint.GetPropEntities()
    local propEntVal = {}
    for _, path in ipairs(BoardwalkSprint.propEnts) do
        table.insert(propEntVal, path)
    end
    return propEntVal
end

local flags = ImGuiWindowFlags.NoTitleBar or ImGuiWindowFlags.NoNavInputs or ImGuiWindowFlags.NoDecoration

function BoardwalkSprint.DrawCustomWindow()
    if BoardwalkSprint.cetopen == false then return end
    local width, height = GetDisplayResolution()
    ImGui.PushStyleColor(ImGuiCol.Header, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Button, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.BorderShadow, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrab, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrabHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrabActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Separator, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.SeparatorHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.SeparatorActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGrip, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGripHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGripActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.0, 1.0, 1.0, 1.1)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.0, 1.0, 1.0, 1.1)
    ImGui.SetNextWindowBgAlpha(0)
    ImGui.SetNextWindowPos(width / 40, height / 1.75, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(width / 5, height / 1.75, ImGuiCond.Always)
    if ImGui.Begin('Kill Counter', true, flags) then
        ImGui.SetWindowFontScale(2.0)
        ImGui.Text('Pedestrians Killed: ' .. tostring(BoardwalkSprint.killcount))
        ImGui.Text('Total Eddies Earned: ' .. tostring(BoardwalkSprint.killcount * 250))
    ImGui.End()
    end
    ImGui.PopStyleColor(28)
end

return BoardwalkSprint
