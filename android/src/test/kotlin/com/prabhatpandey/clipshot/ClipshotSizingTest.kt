package com.prabhatpandey.clipshot

import kotlin.test.Test
import kotlin.test.assertEquals

internal class ClipshotSizingTest {
    @Test
    fun fitsInsideBothBoundsWithoutCropping() {
        assertEquals(Pair(640, 360), calculateTargetSize(1920, 1080, 640, 640))
    }

    @Test
    fun calculatesMissingDimensionProportionally() {
        assertEquals(Pair(800, 450), calculateTargetSize(1920, 1080, 800, null))
        assertEquals(Pair(640, 360), calculateTargetSize(1920, 1080, null, 360))
    }

    @Test
    fun neverUpscales() {
        assertEquals(Pair(320, 180), calculateTargetSize(320, 180, 1920, 1080))
    }

    @Test
    fun recognizesRotationAlreadyAppliedByRetriever() {
        assertEquals(false, shouldApplyRotation(1080, 1920, 1920, 1080, 90))
        assertEquals(false, shouldApplyRotation(1920, 1080, 1920, 1080, 180))
    }

    @Test
    fun compensatesForUnrotatedVendorBitmap() {
        assertEquals(true, shouldApplyRotation(1920, 1080, 1920, 1080, 90))
    }
}
