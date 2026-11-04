//
//  FAPDFTextBridge.kt
//  FurAffinity (Android)
//
//  Reads a story PDF with PdfBox-Android for FAKit's shared `PDFReflow`, reached by name
//  from PDFTextBridge.swift like FAMediaBridge.
//

package fur.affinity.ui

import android.graphics.Bitmap
import android.util.Log
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.contentstream.PDFStreamEngine
import com.tom_roush.pdfbox.contentstream.operator.DrawObject
import com.tom_roush.pdfbox.contentstream.operator.Operator
import com.tom_roush.pdfbox.contentstream.operator.state.Concatenate
import com.tom_roush.pdfbox.contentstream.operator.state.Restore
import com.tom_roush.pdfbox.contentstream.operator.state.Save
import com.tom_roush.pdfbox.contentstream.operator.state.SetGraphicsStateParameters
import com.tom_roush.pdfbox.contentstream.operator.state.SetMatrix
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.rendering.PDFRenderer
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.File
import java.io.StringWriter
import org.json.JSONArray
import org.json.JSONObject
import skip.foundation.ProcessInfo

class FAPDFTextBridge {
    fun pages(path: String, imageDir: String): String = Companion.pages(path, imageDir)

    companion object {
        private const val TAG = "FAPDFTextBridge"
        private const val IMAGE_SCALE = 2f
        private val LIGATURES = mapOf(
            '\uFB00' to "ff", '\uFB01' to "fi", '\uFB02' to "fl", '\uFB03' to "ffi",
            '\uFB04' to "ffl", '\uFB05' to "st", '\uFB06' to "st",
        )

        private val resourcesLoaded: Unit by lazy {
            PDFBoxResourceLoader.init(ProcessInfo.processInfo.androidContext)
        }

        fun pages(path: String, imageDir: String): String = try {
            resourcesLoaded
            PDDocument.load(File(path)).use { document ->
                val stripper = PageStripper()
                stripper.sortByPosition = true
                stripper.writeText(document, StringWriter())
                val renderer = PDFRenderer(document)
                File(imageDir).mkdirs()
                val pages = JSONArray()
                for ((index, page) in stripper.pages.withIndex()) {
                    val pdPage = document.getPage(index)
                    page.put("images", images(pdPage, index, renderer, imageDir))
                    pages.put(page)
                }
                JSONObject().put("pages", pages).toString()
            }
        } catch (e: Exception) {
            Log.e(TAG, "pages failed for $path", e)
            ""
        }

        /// Rendered from the page, so masks and encodings don't matter.
        private fun images(page: PDPage, index: Int, renderer: PDFRenderer, imageDir: String): JSONArray {
            val result = JSONArray()
            val box = page.cropBox
            val rects = ImageLocator().also { it.processPage(page) }.rects
                .filter { it[2] > 1 && it[3] > 1 }
            if (rects.isEmpty()) return result
            val bitmap = renderer.renderImage(index, IMAGE_SCALE)
            for ((n, rect) in rects.withIndex()) {
                val (x, y, width, height) = rect
                val left = ((x - box.lowerLeftX) * IMAGE_SCALE).toInt().coerceIn(0, bitmap.width - 1)
                val top = ((box.upperRightY - (y + height)) * IMAGE_SCALE).toInt().coerceIn(0, bitmap.height - 1)
                val w = (width * IMAGE_SCALE).toInt().coerceAtMost(bitmap.width - left)
                val h = (height * IMAGE_SCALE).toInt().coerceAtMost(bitmap.height - top)
                if (w <= 0 || h <= 0) continue
                val file = File(imageDir, "page$index-$n.png")
                file.outputStream().use {
                    Bitmap.createBitmap(bitmap, left, top, w, h).compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                result.put(JSONObject().put("top", (y + height - box.lowerLeftY).toDouble()).put("path", file.path))
            }
            bitmap.recycle()
            return result
        }
    }

    /// Boxes are in PDF space: origin bottom-left, y up.
    private class PageStripper : PDFTextStripper() {
        val pages = mutableListOf<JSONObject>()
        private val text = StringBuilder()
        private var runs = JSONArray()
        private var boxes = JSONArray()
        private var pageHeight = 0f
        private var runLength = 0
        private var runFont: List<Any>? = null

        override fun startPage(page: PDPage) {
            text.setLength(0)
            runLength = 0
            runFont = null
            pageHeight = page.cropBox.height
            runs = JSONArray()
            boxes = JSONArray()
        }

        override fun endPage(page: PDPage) {
            flushRun()
            pages.add(
                JSONObject()
                    .put("width", page.cropBox.width.toDouble())
                    .put("height", page.cropBox.height.toDouble())
                    .put("text", text.toString())
                    .put("runs", runs)
                    .put("boxes", boxes)
            )
        }

        override fun writeString(string: String, textPositions: MutableList<TextPosition>) {
            for (position in textPositions) {
                val unicode = position.unicode?.let(::expandingLigatures) ?: continue
                val size = position.fontSizeInPt
                val height = if (size > 0) size else position.heightDir
                val minY = pageHeight - position.yDirAdj - height * 0.2f
                val width = position.widthDirAdj / unicode.length
                for ((i, char) in unicode.withIndex()) {
                    append(char, font(position), position.xDirAdj + width * i, minY, width, height)
                }
            }
        }

        /// PDFKit spells these out; matching it keeps words searchable and joinable.
        private fun expandingLigatures(text: String): String =
            if (text.none { it in '\uFB00'..'\uFB06' }) text
            else text.map { LIGATURES[it] ?: it.toString() }.joinToString("")

        override fun writeWordSeparator() = appendSeparator(' ')

        override fun writeLineSeparator() = appendSeparator('\n')

        private fun appendSeparator(char: Char) {
            append(char, runFont ?: listOf(12.0, false, false), 0f, 0f, 0f, 0f)
        }

        /// The PDF's own spaces and PdfBox's separators overlap; keep one.
        private fun append(char: Char, font: List<Any>, x: Float, y: Float, width: Float, height: Float) {
            val last = text.lastOrNull()
            if (char == ' ' && (last == null || last == ' ' || last == '\n')) return
            if (char == '\n' && last == ' ') {
                text.setCharAt(text.length - 1, '\n')
                for (i in 0 until 4) boxes.put(boxes.length() - 4 + i, 0.0)
                return
            }
            if (font != runFont) {
                flushRun()
                runFont = font
            }
            text.append(char)
            runLength += 1
            boxes.put(x.toDouble()).put(y.toDouble()).put(width.toDouble()).put(height.toDouble())
        }

        private fun flushRun() {
            val font = runFont ?: return
            if (runLength > 0) runs.put(JSONArray().put(runLength).put(font[0]).put(font[1]).put(font[2]))
            runLength = 0
        }

        private fun font(position: TextPosition): List<Any> {
            val font = position.font
            val name = font?.name.orEmpty()
            val descriptor = font?.fontDescriptor
            val bold = (descriptor?.isForceBold ?: false) || (descriptor?.fontWeight ?: 0f) >= 600f ||
                Regex("Bold|Black|Heavy|Semibold|Demi", RegexOption.IGNORE_CASE).containsMatchIn(name)
            val italic = (descriptor?.isItalic ?: false) ||
                Regex("Italic|Oblique", RegexOption.IGNORE_CASE).containsMatchIn(name)
            return listOf(position.fontSizeInPt.toDouble(), bold, italic)
        }
    }

    private class ImageLocator : PDFStreamEngine() {
        val rects = mutableListOf<List<Float>>()

        init {
            addOperator(Concatenate())
            addOperator(DrawObject())
            addOperator(SetGraphicsStateParameters())
            addOperator(Save())
            addOperator(Restore())
            addOperator(SetMatrix())
        }

        override fun processOperator(operator: Operator, operands: MutableList<COSBase>) {
            if (operator.name == "Do") {
                val name = operands.firstOrNull() as? COSName ?: return
                when (val xObject = resources.getXObject(name)) {
                    is PDImageXObject -> {
                        val ctm = graphicsState.currentTransformationMatrix
                        rects.add(listOf(ctm.translateX, ctm.translateY, ctm.scalingFactorX, ctm.scalingFactorY))
                    }
                    is PDFormXObject -> showForm(xObject)
                }
            } else {
                super.processOperator(operator, operands)
            }
        }
    }
}
