// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readDimStyle). See NOTICE.md. The field order is the format's own, from the Open Design
// Specification for .dwg files.
//
// Each field is a dimension variable, named for it in the comment, with its DXF group code. The
// file stores every variable. A variable that a release does not store keeps the value AutoCAD
// gives it when a style is new. The values are in drawing units and radians, as the file holds
// them. A switch is a Bool and a mode an Int, the number the file holds.

/// A dimension style: every dimension variable the file stores, and the handles it points at.
struct DimensionStyleData {
    /// The entry and its name.
    var entry = TableEntryCommon()
    /// A bit the format says seems to set bit 1 of the DXF flags.
    var unknownFlag = false

    // MARK: Text and suffixes

    /// DIMPOST (3): a prefix and suffix for the dimension text, `<>` standing for the value.
    var postfix = ""
    /// DIMAPOST (4): the same for the alternate units.
    var alternatePostfix = ""
    /// DIMBLK (5): the name of the arrow block.
    ///
    /// R13 and R14 only, which keep names and not handles.
    var arrowBlockName = ""
    /// DIMBLK1 (6): the name of the first arrow block.
    ///
    /// R13 and R14 only.
    var arrowBlock1Name = ""
    /// DIMBLK2 (7): the name of the second arrow block.
    ///
    /// R13 and R14 only.
    var arrowBlock2Name = ""

    // MARK: Sizes

    /// DIMSCALE (40): the overall scale of the dimension variables.
    var scale = 1.0
    /// DIMASZ (41): the size of the arrowheads.
    var arrowSize = 0.18
    /// DIMEXO (42): the offset of the extension lines from the origin points.
    var extensionLineOffset = 0.0625
    /// DIMDLI (43): the spacing of baseline dimension lines.
    var dimensionLineIncrement = 0.38
    /// DIMEXE (44): how far the extension lines go past the dimension line.
    var extensionLineExtension = 0.18
    /// DIMRND (45): what the dimension values are rounded to.
    var rounding = 0.0
    /// DIMDLE (46): how far the dimension line goes past the extension lines.
    var dimensionLineExtension = 0.0
    /// DIMTP (47): the plus tolerance.
    var plusTolerance = 0.0
    /// DIMTM (48): the minus tolerance.
    var minusTolerance = 0.0
    /// DIMFXL (49): the length of fixed-length extension lines.
    ///
    /// R2007 and later.
    var fixedExtensionLineLength = 1.0
    /// DIMJOGANG (50): the angle of the jog of a jogged radius dimension, in radians.
    ///
    /// R2007 and later.
    var joggedRadiusAngle = Double.pi / 4
    /// DIMTXT (140): the text height.
    var textHeight = 0.18
    /// DIMCEN (141): the size of centre marks, and of centre lines when negative.
    var centerMarkSize = 0.09
    /// DIMTSZ (142): the size of oblique ticks drawn in place of arrowheads.
    var tickSize = 0.0
    /// DIMALTF (143): the factor from the main to the alternate units.
    var alternateScale = 25.4
    /// DIMLFAC (144): the linear measurement scale factor.
    var linearScale = 1.0
    /// DIMTVP (145): the vertical position of the text above or below the dimension line.
    var textVerticalOffset = 0.0
    /// DIMTFAC (146): the scale of the tolerance text against the dimension text.
    var toleranceScale = 1.0
    /// DIMGAP (147): the gap between the dimension line and its text.
    var lineGap = 0.09
    /// DIMALTRND (148): what the alternate units are rounded to.
    ///
    /// R2000 and later.
    var alternateRounding = 0.0

    // MARK: Switches

    /// DIMTOL (71): whether tolerances are added to the text.
    var generateTolerances = false
    /// DIMLIM (72): whether the limits are the text.
    var limitsGeneration = false
    /// DIMTIH (73): whether text inside the extension lines is horizontal.
    var textInsideHorizontal = true
    /// DIMTOH (74): whether text outside the extension lines is horizontal.
    var textOutsideHorizontal = true
    /// DIMSE1 (75): whether the first extension line is left out.
    var suppressExtensionLine1 = false
    /// DIMSE2 (76): whether the second extension line is left out.
    var suppressExtensionLine2 = false
    /// DIMALT (170): whether alternate units are shown.
    var alternateUnits = false
    /// DIMTOFL (172): whether a dimension line is drawn when the text is outside the extension
    /// lines.
    var textOutsideExtensions = false
    /// DIMSAH (173): whether the arrowheads use blocks of their own.
    var separateArrowBlocks = false
    /// DIMTIX (174): whether the text is forced inside the extension lines.
    var textInsideExtensions = false
    /// DIMSOXD (175): whether the dimension line is left out when the arrows are outside.
    var suppressOutsideExtensions = false
    /// DIMSD1 (281): whether the first dimension line is left out.
    var suppressDimensionLine1 = false
    /// DIMSD2 (282): whether the second dimension line is left out.
    var suppressDimensionLine2 = false
    /// DIMUPT (288): whether the text position is updated as the cursor moves.
    var cursorUpdate = false
    /// DIMFXLON (290): whether the extension lines have a fixed length.
    ///
    /// R2007 and later.
    var isExtensionLineLengthFixed = false
    /// DIMTXTDIRECTION (295): whether the text reads right to left.
    ///
    /// R2010 and later.
    var textRightToLeft = false

    // MARK: Modes

    /// DIMTAD (77): where the text sits against the dimension line.
    var textVerticalPosition = 0
    /// DIMZIN (78): which zeros are left out of the main values.
    var zeroSuppression = 0
    /// DIMAZIN (79): which zeros are left out of angles.
    ///
    /// R2000 and later.
    var angularZeroSuppression = 0
    /// DIMARCSYM (90): where the arc symbol goes in an arc length dimension.
    ///
    /// R2007 and later.
    var arcLengthSymbol = 0
    /// DIMTFILL (69): the background of the text.
    ///
    /// R2007 and later.
    var textBackgroundFill = 0
    /// DIMALTD (171): the decimal places of the alternate units.
    var alternateDecimals = 2
    /// DIMADEC (179): the decimal places of angles.
    ///
    /// R2000 and later.
    var angularDecimals = 0
    /// DIMUNIT (270): the units of the dimensions.
    ///
    /// R13 and R14 only, where DIMLUNIT does not exist.
    var unit = 2
    /// DIMDEC (271): the decimal places of the main values.
    var decimals = 4
    /// DIMTDEC (272): the decimal places of the tolerances.
    var toleranceDecimals = 4
    /// DIMALTU (273): the format of the alternate units.
    var alternateUnitFormat = 2
    /// DIMALTTD (274): the decimal places of the alternate tolerances.
    var alternateToleranceDecimals = 2
    /// DIMAUNIT (275): the format of angles.
    var angularUnitFormat = 0
    /// DIMFRAC (276): the format of fractions.
    ///
    /// R2000 and later.
    var fractionFormat = 0
    /// DIMLUNIT (277): the format of the main units.
    ///
    /// R2000 and later.
    var linearUnitFormat = 2
    /// DIMDSEP (278): the character code of the decimal separator.
    ///
    /// R2000 and later.
    var decimalSeparator = 46
    /// DIMTMOVE (279): what moves when the text does.
    ///
    /// R2000 and later.
    var textMovement = 0
    /// DIMJUST (280): the horizontal position of the text.
    var textJustification = 0
    /// DIMTOLJ (283): the vertical justification of tolerances.
    var toleranceJustification = 1
    /// DIMTZIN (284): which zeros are left out of the tolerances.
    var toleranceZeroSuppression = 0
    /// DIMALTZ (285): which zeros are left out of the alternate values.
    var alternateZeroSuppression = 0
    /// DIMALTTZ (286): which zeros are left out of the alternate tolerances.
    var alternateToleranceZeroSuppression = 0
    /// How text and arrows are fitted when there is not room for both.
    ///
    /// R13 and R14 store DIMFIT (287) here. From R2000 the file has one value at this place, which
    /// ACadSharp calls DIMFIT and which the DXF of those releases calls DIMATFIT (289). The
    /// samples hold 3, the default of both, so they do not say which it is.
    var fit = 3

    // MARK: Colours and weights

    /// DIMCLRD (176): the colour of the dimension lines.
    var dimensionLineColor: DWGColor = .byBlock
    /// DIMCLRE (177): the colour of the extension lines.
    var extensionLineColor: DWGColor = .byBlock
    /// DIMCLRT (178): the colour of the text.
    var textColor: DWGColor = .byBlock
    /// DIMTFILLCLR (70): the colour of the text background.
    ///
    /// R2007 and later.
    var textBackgroundColor: DWGColor = .byBlock
    /// DIMLWD (371): the line weight of the dimension lines, in hundredths of a millimetre or -1 by
    /// layer, -2 by block, -3 default.
    ///
    /// R2000 and later.
    var dimensionLineWeight = -2
    /// DIMLWE (372): the line weight of the extension lines, coded as DIMLWD.
    ///
    /// R2000 and later.
    var extensionLineWeight = -2

    // MARK: Multiplier text

    /// DIMALTMZF: the scale of the alternate units' multiplier text.
    ///
    /// R2010 and later.
    var alternateMultiplierFactor = 100.0
    /// DIMALTMZS: the alternate units' multiplier text.
    ///
    /// R2010 and later.
    var alternateMultiplierText = ""
    /// DIMMZF: the scale of the multiplier text.
    ///
    /// R2010 and later.
    var multiplierFactor = 100.0
    /// DIMMZS: the multiplier text.
    ///
    /// R2010 and later.
    var multiplierText = ""

    // MARK: Handles

    /// The block record of the external reference the style came from, if any.
    var externalReference: UInt64 = 0
    /// DIMTXSTY (340): the text style.
    var textStyle: UInt64 = 0
    /// DIMLDRBLK (341): the arrow block of leaders.
    ///
    /// R2000 and later.
    var leaderArrow: UInt64 = 0
    /// DIMBLK (342): the arrow block.
    ///
    /// R2000 and later.
    var arrowBlock: UInt64 = 0
    /// DIMBLK1 (343): the first arrow block.
    ///
    /// R2000 and later.
    var arrowBlock1: UInt64 = 0
    /// DIMBLK2 (344): the second arrow block.
    ///
    /// R2000 and later.
    var arrowBlock2: UInt64 = 0
    /// DIMLTYPE (345): the line type of the dimension lines.
    ///
    /// R2007 and later.
    var dimensionLineType: UInt64 = 0
    /// DIMLTEX1 (346): the line type of the first extension line.
    ///
    /// R2007 and later.
    var extensionLine1Type: UInt64 = 0
    /// DIMLTEX2 (347): the line type of the second extension line.
    ///
    /// R2007 and later.
    var extensionLine2Type: UInt64 = 0
}

extension ObjectReader {
    mutating func readDimensionStyle() throws -> DimensionStyleData {
        var data = DimensionStyleData()
        data.entry = try readTableEntryCommon()

        if version <= .ac1014 { try readOldDimensionVariables(into: &data) }

        if version >= .ac1015 {
            data.postfix = try readText()
            data.alternatePostfix = try readText()
            data.scale = try main.readBitDouble()
            data.arrowSize = try main.readBitDouble()
            data.extensionLineOffset = try main.readBitDouble()
            data.dimensionLineIncrement = try main.readBitDouble()
            data.extensionLineExtension = try main.readBitDouble()
            data.rounding = try main.readBitDouble()
            data.dimensionLineExtension = try main.readBitDouble()
            data.plusTolerance = try main.readBitDouble()
            data.minusTolerance = try main.readBitDouble()
        }
        if version >= .ac1021 {
            data.fixedExtensionLineLength = try main.readBitDouble()
            data.joggedRadiusAngle = try main.readBitDouble()
            data.textBackgroundFill = Int(try main.readBitShort())
            data.textBackgroundColor = try readCmColor()
        }
        if version >= .ac1015 {
            data.generateTolerances = try main.readBit()
            data.limitsGeneration = try main.readBit()
            data.textInsideHorizontal = try main.readBit()
            data.textOutsideHorizontal = try main.readBit()
            data.suppressExtensionLine1 = try main.readBit()
            data.suppressExtensionLine2 = try main.readBit()
            data.textVerticalPosition = Int(try main.readBitShort())
            data.zeroSuppression = Int(try main.readBitShort())
            data.angularZeroSuppression = Int(try main.readBitShort())
        }
        if version >= .ac1021 { data.arcLengthSymbol = Int(try main.readBitShort()) }
        if version >= .ac1015 { try readCurrentDimensionVariables(into: &data) }
        if version >= .ac1021 { data.isExtensionLineLengthFixed = try main.readBit() }
        if version >= .ac1024 {
            data.textRightToLeft = try main.readBit()
            data.alternateMultiplierFactor = try main.readBitDouble()
            data.alternateMultiplierText = try readText()
            data.multiplierFactor = try main.readBitDouble()
            data.multiplierText = try readText()
        }
        if version >= .ac1015 {
            data.dimensionLineWeight = Int(try main.readBitShort())
            data.extensionLineWeight = Int(try main.readBitShort())
        }

        data.unknownFlag = try main.readBit()

        data.externalReference = try readOwnHandle()
        data.textStyle = try readOwnHandle()
        if version >= .ac1015 {
            data.leaderArrow = try readOwnHandle()
            data.arrowBlock = try readOwnHandle()
            data.arrowBlock1 = try readOwnHandle()
            data.arrowBlock2 = try readOwnHandle()
        }
        if version >= .ac1021 {
            data.dimensionLineType = try readOwnHandle()
            data.extensionLine1Type = try readOwnHandle()
            data.extensionLine2Type = try readOwnHandle()
        }
        return data
    }

    /// Reads the variables of R13 and R14, which keep them in a different order and in smaller
    /// codes than the later releases.
    ///
    /// ACadSharp's assignments for DIMTIH, DIMTOH, DIMSE1 and DIMSE2 here are rotated by one place
    /// against the names its own comments give. This follows the variable each position is named
    /// for.
    private mutating func readOldDimensionVariables(into data: inout DimensionStyleData) throws {
        data.generateTolerances = try main.readBit()
        data.limitsGeneration = try main.readBit()
        data.textInsideHorizontal = try main.readBit()
        data.textOutsideHorizontal = try main.readBit()
        data.suppressExtensionLine1 = try main.readBit()
        data.suppressExtensionLine2 = try main.readBit()
        data.alternateUnits = try main.readBit()
        data.textOutsideExtensions = try main.readBit()
        data.separateArrowBlocks = try main.readBit()
        data.textInsideExtensions = try main.readBit()
        data.suppressOutsideExtensions = try main.readBit()
        data.alternateDecimals = Int(try main.readByte())
        data.zeroSuppression = Int(try main.readByte())
        data.suppressDimensionLine1 = try main.readBit()
        data.suppressDimensionLine2 = try main.readBit()
        data.toleranceJustification = Int(try main.readByte())
        data.textJustification = Int(try main.readByte())
        data.fit = Int(try main.readByte())
        data.cursorUpdate = try main.readBit()
        data.toleranceZeroSuppression = Int(try main.readByte())
        data.alternateZeroSuppression = Int(try main.readByte())
        data.alternateToleranceZeroSuppression = Int(try main.readByte())
        data.textVerticalPosition = Int(try main.readByte())
        data.unit = Int(try main.readBitShort())
        data.angularUnitFormat = Int(try main.readBitShort())
        data.decimals = Int(try main.readBitShort())
        data.toleranceDecimals = Int(try main.readBitShort())
        data.alternateUnitFormat = Int(try main.readBitShort())
        data.alternateToleranceDecimals = Int(try main.readBitShort())
        data.scale = try main.readBitDouble()
        data.arrowSize = try main.readBitDouble()
        data.extensionLineOffset = try main.readBitDouble()
        data.dimensionLineIncrement = try main.readBitDouble()
        data.extensionLineExtension = try main.readBitDouble()
        data.rounding = try main.readBitDouble()
        data.dimensionLineExtension = try main.readBitDouble()
        data.plusTolerance = try main.readBitDouble()
        data.minusTolerance = try main.readBitDouble()
        data.textHeight = try main.readBitDouble()
        data.centerMarkSize = try main.readBitDouble()
        data.tickSize = try main.readBitDouble()
        data.alternateScale = try main.readBitDouble()
        data.linearScale = try main.readBitDouble()
        data.textVerticalOffset = try main.readBitDouble()
        data.toleranceScale = try main.readBitDouble()
        data.lineGap = try main.readBitDouble()
        data.postfix = try readText()
        data.alternatePostfix = try readText()
        data.arrowBlockName = try readText()
        data.arrowBlock1Name = try readText()
        data.arrowBlock2Name = try readText()
        data.dimensionLineColor = try readColorIndex()
        data.extensionLineColor = try readColorIndex()
        data.textColor = try readColorIndex()
    }

    /// Reads the variables that R2000 and later keep after the tolerance switches.
    private mutating func readCurrentDimensionVariables(
        into data: inout DimensionStyleData
    ) throws {
        data.textHeight = try main.readBitDouble()
        data.centerMarkSize = try main.readBitDouble()
        data.tickSize = try main.readBitDouble()
        data.alternateScale = try main.readBitDouble()
        data.linearScale = try main.readBitDouble()
        data.textVerticalOffset = try main.readBitDouble()
        data.toleranceScale = try main.readBitDouble()
        data.lineGap = try main.readBitDouble()
        data.alternateRounding = try main.readBitDouble()
        data.alternateUnits = try main.readBit()
        data.alternateDecimals = Int(try main.readBitShort())
        data.textOutsideExtensions = try main.readBit()
        data.separateArrowBlocks = try main.readBit()
        data.textInsideExtensions = try main.readBit()
        data.suppressOutsideExtensions = try main.readBit()
        data.dimensionLineColor = try readCmColor()
        data.extensionLineColor = try readCmColor()
        data.textColor = try readCmColor()
        data.angularDecimals = Int(try main.readBitShort())
        data.decimals = Int(try main.readBitShort())
        data.toleranceDecimals = Int(try main.readBitShort())
        data.alternateUnitFormat = Int(try main.readBitShort())
        data.alternateToleranceDecimals = Int(try main.readBitShort())
        data.angularUnitFormat = Int(try main.readBitShort())
        data.fractionFormat = Int(try main.readBitShort())
        data.linearUnitFormat = Int(try main.readBitShort())
        data.decimalSeparator = Int(try main.readBitShort())
        data.textMovement = Int(try main.readBitShort())
        data.textJustification = Int(try main.readBitShort())
        data.suppressDimensionLine1 = try main.readBit()
        data.suppressDimensionLine2 = try main.readBit()
        data.toleranceJustification = Int(try main.readBitShort())
        data.toleranceZeroSuppression = Int(try main.readBitShort())
        data.alternateZeroSuppression = Int(try main.readBitShort())
        data.alternateToleranceZeroSuppression = Int(try main.readBitShort())
        data.cursorUpdate = try main.readBit()
        data.fit = Int(try main.readBitShort())
    }
}
