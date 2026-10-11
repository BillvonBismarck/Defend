-- 几何内核回归：尺寸、面积比、端口、走廊、阶梯十二边与 SAT 判定。纯 CPU，无引擎/文件依赖。
local T = {}
local Lattice = require("defense.Lattice")

local function near(a, b) return math.abs(a - b) < 0.001 end

function T.Register(case)
    case("L01_尺寸与面积契约", function(t)
        t:Check(Lattice.Validate(), "定稿契约校验")
        t:Equal(Lattice.Spec("tri").edge, 10, "三角边长 10u")
        t:Equal(Lattice.Spec("hex").edge, 6, "六边边长 6u")
        t:Equal(Lattice.Spec("dodeca").edge, 4, "十二边边长 4u")
        t:Equal(Lattice.Spec("tri").area, 100, "三角面积 100 单位三角")
        t:Equal(Lattice.Spec("hex").area, 216, "六边面积 216 单位三角")
        t:Equal(Lattice.Spec("dodeca").area, 400, "十二边面积 400 单位三角（阶梯取整）")
    end)

    case("L02_面积比 1:2.16:4.00", function(t)
        local tri, hex, dodeca = Lattice.Spec("tri").area, Lattice.Spec("hex").area, Lattice.Spec("dodeca").area
        t:Near(hex / tri, 2.16, "六边/三角")
        t:Near(dodeca / tri, 4.00, "十二边/三角")
        t:Near(dodeca / hex, 400 / 216, "十二边/六边")
    end)

    case("L03_内外接半径", function(t)
        t:Near(Lattice.Inradius("tri"), 10 / (2 * math.tan(math.pi / 3)), "三角内切")
        t:Near(Lattice.Circumradius("tri"), 10 / (2 * math.sin(math.pi / 3)), "三角外接")
        t:Near(Lattice.Inradius("hex"), 6 * math.sqrt(3) / 2, "六边内切")
        t:Near(Lattice.Circumradius("hex"), 6.0, "六边外接")
        t:Near(Lattice.Inradius("dodeca"), 4 / (2 * math.tan(math.pi / 12)), "十二边内切")
        t:Near(Lattice.Circumradius("dodeca"), 4 / (2 * math.sin(math.pi / 12)), "十二边外接")
        t:Near(Lattice.Inradius("tri"), 10 / (2 * math.tan(math.pi / 3)), "三角内切精确值")
        t:Check(math.abs(Lattice.Inradius("tri") - 2.8868) < 0.001, "三角内切 ≈2.89u")
        t:Check(math.abs(Lattice.Inradius("hex") - 5.1962) < 0.001, "六边内切 ≈5.20u")
        t:Check(math.abs(Lattice.Inradius("dodeca") - 7.4641) < 0.001, "十二边内切 ≈7.46u")
        t:Check(Lattice.Inradius("tri") < Lattice.Inradius("hex"), "内切半径递增 三角<六边")
        t:Check(Lattice.Inradius("hex") < Lattice.Inradius("dodeca"), "内切半径递增 六边<十二边")
    end)

    case("L04_端口方向与朝向类别", function(t)
        t:Equal(Lattice.RotationCount("tri"), 2, "三角 2 类朝向")
        t:Equal(Lattice.RotationCount("hex"), 1, "六边 1 类朝向")
        t:Equal(Lattice.RotationCount("dodeca"), 1, "十二边 1 类朝向")
        for _, kind in ipairs(Lattice.Kinds) do
            for rotation = 0, Lattice.RotationCount(kind) - 1 do
                for _, dir in ipairs(Lattice.PortNormals(kind, rotation)) do
                    t:Check(Lattice.IsOddDirection(dir), kind .. " 端口必须落在奇数方向:" .. tostring(dir))
                end
            end
        end
        t:Equal(Lattice.RotationFacing("tri", 270), 0, "三角朝上类别（端口 30/150/270）")
        t:Equal(Lattice.RotationFacing("tri", 90), 1, "三角朝下类别（端口 90/210/330）")
        t:Equal(Lattice.RotationFacing("hex", 123), nil, "奇数方向之外无端口")
        local up = { id = "A", kind = "tri", rotation = 0, x = 0, y = 0 }
        for _, dir in ipairs(Lattice.PortNormals("tri", 0)) do
            local px, py = Lattice.PortPoint(up, Lattice.PortIndexFacing(up, dir))
            local angle = math.deg(math.atan(py, px)) % 360
            t:Near(angle, dir % 360, "三角端口点必须落在法线方向上")
        end
    end)

    case("L05_走廊长度区间", function(t)
        t:Check(Lattice.LegalCorridorLength(2), "下限 2u 合法")
        t:Check(Lattice.LegalCorridorLength(4), "上限 4u 合法")
        t:Check(not Lattice.LegalCorridorLength(1.9), "小于 2u 非法")
        t:Check(not Lattice.LegalCorridorLength(4.1), "大于 4u 非法")
        t:Equal(Lattice.CorridorWidth, 2, "走廊宽度恒为 2u")
        local main = { id = "A", kind = "hex", rotation = 0, x = 0, y = 0 }
        local ok = pcall(function() Lattice.Place(main, 1, "hex", 5) end)
        t:Check(not ok, "越界长度必须报错")
    end)

    case("L06_中心距公式", function(t)
        local rtri, rhex, rdodeca = Lattice.Inradius("tri"), Lattice.Inradius("hex"), Lattice.Inradius("dodeca")
        t:Near(Lattice.CenterDistance("tri", "tri", 3), 2 * rtri + 3, "三角-三角")
        t:Near(Lattice.CenterDistance("tri", "hex", 3), rtri + rhex + 3, "三角-六边")
        t:Near(Lattice.CenterDistance("tri", "dodeca", 3), rtri + rdodeca + 3, "三角-十二边")
        t:Near(Lattice.CenterDistance("hex", "hex", 3), 2 * rhex + 3, "六边-六边")
        t:Near(Lattice.CenterDistance("hex", "dodeca", 3), rhex + rdodeca + 3, "六边-十二边")
        t:Near(Lattice.CenterDistance("dodeca", "dodeca", 3), 2 * rdodeca + 3, "十二边-十二边")
        t:Near(Lattice.CenterDistance("tri", "tri", 3), 8.7735, "三角-三角 ≈8.77u")
        t:Near(Lattice.CenterDistance("hex", "hex", 3), 13.3923, "六边-六边 ≈13.39u")
        t:Near(Lattice.CenterDistance("dodeca", "dodeca", 3), 17.9282, "十二边-十二边 ≈17.93u")
    end)

    case("L07_端口点等于边中点", function(t)
        local room = { id = "A", kind = "hex", rotation = 0, x = 10, y = -4 }
        for index = 1, 6 do
            local px, py = Lattice.PortPoint(room, index)
            local d = math.sqrt((px - room.x) ^ 2 + (py - room.y) ^ 2)
            t:Near(d, Lattice.Inradius("hex"), "端口点到中心 = 内切半径")
        end
        local tri = { id = "B", kind = "tri", rotation = 0, x = 0, y = 0 }
        local placed, dir, back = Lattice.Place(tri, Lattice.PortIndexFacing(tri, 30), "hex", 3)
        t:Check(Lattice.PortIndexFacing(placed, (dir + 180) % 360) ~= nil, "新房间必须正对父端口反向")
        t:Equal(back, (dir + 180) % 360, "反向方向计算")
    end)

    case("L08_十二边阶梯取整", function(t)
        local geometry = Lattice.DodecagonGeometry()
        t:Check(geometry.raw >= 380 and geometry.raw <= 420, "阶梯求并应在理想面积附近:" .. geometry.raw)
        t:Equal(#geometry.cells, Lattice.DodecagonCellTarget, "裁剪到 400 个单位三角")
        t:Equal(Lattice.DodecagonArea(), 400, "十二边面积取整")
        t:Check(geometry.cells[1].d <= geometry.cells[#geometry.cells].d, "裁剪按中心距离升序（保留内部）")
    end)

    case("L09_房间重叠判定", function(t)
        local a = { id = "A", kind = "hex", rotation = 0, x = 0, y = 0 }
        local same = { id = "B", kind = "hex", rotation = 0, x = 1, y = 1 }
        local far = { id = "C", kind = "hex", rotation = 0, x = 40, y = 0 }
        local linked = { id = "D", kind = "hex", rotation = 0, x = Lattice.CenterDistance("hex", "hex", 3), y = 0 }
        t:Check(Lattice.RoomsOverlap(a, same), "重叠必须判定为重叠")
        t:Check(not Lattice.RoomsOverlap(a, far), "远离必须判定为不重叠")
        t:Check(not Lattice.RoomsOverlap(a, linked), "合法走廊间隔不得判定为重叠")
        local tri = { id = "E", kind = "tri", rotation = 0, x = 0, y = 0 }
        local port = Lattice.PortIndexFacing(tri, 30)
        local triNear = Lattice.Place(tri, port, "tri", 2)
        t:Check(not Lattice.RoomsOverlap(tri, triNear, 0), "最短三角连接（L=2u）不得重叠")
        local triTight = Lattice.Place(tri, port, "tri", 2)
        local shift = 2.5
        triTight.x = triTight.x - shift * math.cos(math.rad(30))
        triTight.y = triTight.y - shift * math.sin(math.rad(30))
        t:Check(Lattice.RoomsOverlap(tri, triTight, 0), "沿端口轴贴近 2.5u 必须判定为重叠")
    end)

    case("L10_槽位与墙段契约", function(t)
        t:Equal(Lattice.Spec("tri").slots, 1, "三角 1 槽（中心）")
        t:Equal(Lattice.Spec("tri").slot_kind, "center", "三角槽位在中心")
        t:Equal(Lattice.Spec("hex").slots, 3, "六边 3 槽")
        t:Equal(Lattice.Spec("dodeca").slots, 12, "十二边 12 槽")
        t:Equal(Lattice.Perimeter("tri"), 30, "三角周长 30u（30 段墙）")
        t:Equal(Lattice.Perimeter("hex"), 36, "六边周长 36u")
        t:Equal(Lattice.Perimeter("dodeca"), 48, "十二边周长 48u（阶梯后 48–50 段）")
    end)
end

return T
