local UI = require("urhox-libs/UI")
local T = {}
T.C = {
    bg = { 7, 11, 20, 236 }, panel = { 10, 16, 28, 248 }, rail = { 12, 20, 34, 255 },
    card = { 16, 26, 44, 255 }, widget = { 22, 36, 56, 255 }, cardLit = { 30, 48, 78, 255 },
    cyan = { 0, 229, 208, 255 }, cyanDim = { 0, 150, 148, 220 }, cyanSoft = { 0, 150, 148, 80 },
    ink = { 4, 8, 16, 255 }, text = { 240, 248, 252, 255 }, dim = { 120, 148, 162, 255 },
    warn = { 255, 196, 72, 255 }, orange={255,155,50,255},error = { 232, 93, 91, 255 }, blue = { 77, 177, 255, 255 },
    purple = { 160, 146, 210, 255 }, pink = { 213, 143, 169, 255 }, green = { 140, 203, 143, 255 },
    ghost = { 116, 156, 176, 255 }, floor = { 14, 23, 38, 255 }, hall = { 18, 30, 48, 255 }, wall = { 7, 12, 22, 255 },
}
T.HP, T.XP, T.Gold, T.Trail = { 232, 93, 91, 255 }, T.C.cyan, T.C.warn, T.C.text
T.ICON_PATHS = {
    core = "image/defense/ui_icon_core_darktech_20261007.png",
    turret = "image/defense/ui_icon_turret_darktech_20261007.png",
    repair = "image/defense/ui_icon_repair_darktech_20261007.png",
}

function T.TextSize(requested)
    return requested <= 13.5 and 13.5 or 18
end

function T.Create()
    local C = T.C
    return UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf", bold = "Fonts/MiSans-Regular.ttf" } },
            { family = "pixel", weights = { normal = "Fonts/zpix.ttf", bold = "Fonts/zpix.ttf" } },
        },
        typography = { fontFamily = "pixel", h1 = { fontSize = 18 }, h2 = { fontSize = 18 },
            h3 = { fontSize = 18 }, body = { fontSize = 13.5 }, bodySmall = { fontSize = 13.5 }, caption = { fontSize = 13.5 } },
        colors = {
            background = C.panel, surface = C.card, surfaceAlt = C.rail, surfaceHover = C.widget,
            primary = C.cyan, primaryHover = { 38, 239, 219, 255 }, primaryPressed = C.cyanDim,
            secondary = C.card, secondaryHover = C.widget, secondaryPressed = C.rail,
            border = C.cyanSoft, borderFocus = C.cyan, text = C.text, textSecondary = C.dim,
            textDisabled = C.dim, disabledText = C.dim, disabled = C.rail, disabledBorder = C.widget,
            success = C.cyan, successHover = { 38, 239, 219, 255 }, successPressed = C.cyanDim,
            info = C.blue, warning = C.warn, error = C.error, danger = C.error,
            errorHover = { 245, 122, 116, 255 }, errorPressed = { 192, 69, 71, 255 },
            overlay = C.bg, hover = { 0, 229, 208, 20 },
        },
        radius = { none = 0, xs = 3, sm = 4, md = 6, lg = 8, xl = 10, full = 11 },
        componentDefaults = { borderRadius = 4, fontFamily = "pixel", fontSize = 13.5,
            fontWeight = "normal", shadowBlur = 0 },
        components = {
            Button = { height = 44, fontFamily = "pixel", fontSize = 13.5, borderRadius = 4, borderWidth = 1,
                padding = { 6, 12 }, fontWeight = "normal", shadowBlur = 0,
                transition = "backgroundColor 0.12s easeOut",
                variantTextColor = { primary = C.ink, success = C.ink, secondary = C.text, danger = C.ink } },
            Panel = { borderRadius = 6 }, Card = { borderRadius = 6, borderWidth = 1, borderColor = C.cyanSoft },
            Label = { fontFamily = "pixel", fontSize = 13.5, fontWeight = "normal", fontColor = C.text },
            Checkbox = { fontFamily = "pixel", fontSize = 13.5, borderRadius = 3 },
            ProgressBar = { height = 8, borderRadius = 3 },
            Slider = { trackColor = C.widget, fillColor = C.cyan, thumbColor = C.text },
            ScrollView = { scrollbarColor = C.cyanDim },
            Modal = { borderRadius = 8, borderWidth = 1, headerBgColor = C.panel,
                contentBgColor = C.rail, titleTextColor = C.text },
        },
    })
end
function T.Atmosphere(elapsed)
    return 0.08 + 0.06 * (0.5 + 0.5 * math.sin(elapsed * 0.4))
end
return T
