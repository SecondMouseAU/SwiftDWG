// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLayout, readPlotSettings). See NOTICE.md. The field order is the format's own, from the Open
// Design Specification for .dwg files.

import SwiftDXF

/// The plot settings a layout starts with.
struct PlotSettingsData {
    /// The name of the page setup (DXF 1).
    var pageSetupName = ""
    /// The printer or plot configuration file (DXF 2).
    var printerName = ""
    /// The plot layout flags (DXF 70).
    var flags = 0
    /// The unprintable margin on the left, in millimetres (DXF 40).
    var leftMargin = 0.0
    /// The unprintable margin at the bottom (DXF 41).
    var bottomMargin = 0.0
    /// The unprintable margin on the right (DXF 42).
    var rightMargin = 0.0
    /// The unprintable margin at the top (DXF 43).
    var topMargin = 0.0
    /// The paper width in millimetres (DXF 44).
    var paperWidth = 0.0
    /// The paper height in millimetres (DXF 45).
    var paperHeight = 0.0
    /// The paper size name (DXF 4).
    var paperSize = ""
    /// The plot origin along x in millimetres (DXF 46).
    var plotOriginX = 0.0
    /// The plot origin along y in millimetres (DXF 47).
    var plotOriginY = 0.0
    /// The paper units: 0 inches, 1 millimetres, 2 pixels (DXF 72).
    var paperUnits = 0
    /// The plot rotation (DXF 73).
    var rotation = 0
    /// What is plotted: display, extents, limits, view, window or layout (DXF 74).
    var plotType = 0
    /// The lower left corner of the plot window (DXF 48 and 49).
    var windowMin: (x: Double, y: Double) = (0, 0)
    /// The upper right corner of the plot window (DXF 140 and 141).
    var windowMax: (x: Double, y: Double) = (0, 0)
    /// The name of the plotted view (DXF 6).
    ///
    /// R13 to R2000 only.
    var plotViewName = ""
    /// The numerator of the custom print scale (DXF 142).
    var scaleNumerator = 1.0
    /// The denominator of the custom print scale (DXF 143).
    var scaleDenominator = 1.0
    /// The plot style sheet (DXF 7).
    var styleSheet = ""
    /// The standard scale type (DXF 75).
    var scaleType = 0
    /// The scale factor (DXF 147).
    var scaleFactor = 1.0
    /// The origin of the paper image (DXF 148 and 149).
    var paperImageOrigin: (x: Double, y: Double) = (0, 0)
    /// How shaded viewports are plotted (DXF 76).
    ///
    /// R2004 and later.
    var shadePlotMode = 0
    /// The resolution level of shaded plots (DXF 77).
    ///
    /// R2004 and later.
    var shadePlotResolution = 0
    /// The custom resolution of shaded plots in dots per inch (DXF 78).
    ///
    /// R2004 and later.
    var shadePlotDPI = 0
    /// The plotted view (DXF 6, as a handle).
    ///
    /// R2004 and later.
    var plotView: UInt64 = 0
    /// The visual style of the plot.
    ///
    /// R2007 and later.
    var visualStyle: UInt64 = 0
}

/// A layout: the plot settings, and the paper space or model space that the layout shows.
struct LayoutData {
    /// The owner, reactors and extension dictionary of the layout.
    var object = ObjectReader.ObjectCommon()
    /// The plot settings the layout starts with.
    var plot = PlotSettingsData()
    /// The name of the layout (DXF 1 of the layout part).
    var name = ""
    /// The position of the layout's tab (DXF 71).
    var tabOrder = 0
    /// The layout flags (DXF 70 of the layout part).
    var flags = 0
    /// The origin of the layout's UCS (DXF 13).
    var ucsOrigin = DXF.Point(0, 0, 0)
    /// The lower left limit (DXF 10).
    var limitsMin: (x: Double, y: Double) = (0, 0)
    /// The upper right limit (DXF 11).
    var limitsMax: (x: Double, y: Double) = (0, 0)
    /// The insertion base point (DXF 12).
    var insertionBase = DXF.Point(0, 0, 0)
    /// The direction of the UCS's x axis (DXF 16).
    var ucsXAxis = DXF.Point(1, 0, 0)
    /// The direction of the UCS's y axis (DXF 17).
    var ucsYAxis = DXF.Point(0, 1, 0)
    /// The elevation (DXF 146).
    var elevation = 0.0
    /// The orthographic type of the UCS (DXF 76 of the layout part).
    var orthographicType = 0
    /// The lower extent of the layout's entities (DXF 14).
    var extentsMin = DXF.Point(0, 0, 0)
    /// The upper extent of the layout's entities (DXF 15).
    var extentsMax = DXF.Point(0, 0, 0)
    /// The block record the layout is the space of (DXF 330 of the layout part).
    var paperSpaceBlock: UInt64 = 0
    /// The viewport that was active last (DXF 331).
    var lastActiveViewport: UInt64 = 0
    /// The base UCS (DXF 346).
    var baseUCS: UInt64 = 0
    /// The named UCS (DXF 345).
    var namedUCS: UInt64 = 0
    /// The viewports of the layout.
    ///
    /// R2004 and later.
    var viewports: [UInt64] = []
}

extension ObjectReader {
    mutating func readLayout() throws -> LayoutData {
        var data = LayoutData()
        data.object = try readObjectCommon()
        data.plot = try readPlotSettings()

        data.name = try readText()
        data.tabOrder = Int(try main.readBitLong())
        data.flags = Int(try main.readBitShort())
        data.ucsOrigin = point(try main.read3BitDouble())
        data.limitsMin = try main.read2RawDouble()
        data.limitsMax = try main.read2RawDouble()
        data.insertionBase = point(try main.read3BitDouble())
        data.ucsXAxis = point(try main.read3BitDouble())
        data.ucsYAxis = point(try main.read3BitDouble())
        data.elevation = try main.readBitDouble()
        data.orthographicType = Int(try main.readBitShort())
        data.extentsMin = point(try main.read3BitDouble())
        data.extentsMax = point(try main.read3BitDouble())

        var viewportCount: Int32 = 0
        if version >= .ac1018 { viewportCount = try main.readBitLong() }

        data.paperSpaceBlock = try readOwnHandle()
        data.lastActiveViewport = try readOwnHandle()
        data.baseUCS = try readOwnHandle()
        data.namedUCS = try readOwnHandle()
        if version >= .ac1018 {
            let count = try checkedHandleCount(viewportCount, "viewports in a layout")
            data.viewports.reserveCapacity(count)
            for _ in 0..<count { data.viewports.append(try readOwnHandle()) }
        }
        return data
    }

    /// Reads the plot settings, which are the first part of a layout.
    mutating func readPlotSettings() throws -> PlotSettingsData {
        var plot = PlotSettingsData()
        plot.pageSetupName = try readText()
        plot.printerName = try readText()
        plot.flags = Int(try main.readBitShort())
        plot.leftMargin = try main.readBitDouble()
        plot.bottomMargin = try main.readBitDouble()
        plot.rightMargin = try main.readBitDouble()
        plot.topMargin = try main.readBitDouble()
        plot.paperWidth = try main.readBitDouble()
        plot.paperHeight = try main.readBitDouble()
        plot.paperSize = try readText()
        plot.plotOriginX = try main.readBitDouble()
        plot.plotOriginY = try main.readBitDouble()
        plot.paperUnits = Int(try main.readBitShort())
        plot.rotation = Int(try main.readBitShort())
        plot.plotType = Int(try main.readBitShort())
        plot.windowMin = try main.read2BitDouble()
        plot.windowMax = try main.read2BitDouble()
        if version >= .ac1012, version <= .ac1015 { plot.plotViewName = try readText() }
        plot.scaleNumerator = try main.readBitDouble()
        plot.scaleDenominator = try main.readBitDouble()
        plot.styleSheet = try readText()
        plot.scaleType = Int(try main.readBitShort())
        plot.scaleFactor = try main.readBitDouble()
        plot.paperImageOrigin = try main.read2BitDouble()
        if version >= .ac1018 {
            plot.shadePlotMode = Int(try main.readBitShort())
            plot.shadePlotResolution = Int(try main.readBitShort())
            plot.shadePlotDPI = Int(try main.readBitShort())
            plot.plotView = try readOwnHandle()
        }
        if version >= .ac1021 { plot.visualStyle = try readOwnHandle() }
        return plot
    }

    private func point(_ triple: (x: Double, y: Double, z: Double)) -> DXF.Point {
        DXF.Point(triple.x, triple.y, triple.z)
    }
}
