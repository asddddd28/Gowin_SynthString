"""Real Tk bounding-box checks for compact and normal matrix layouts."""
import time
import tkinter as tk
import unittest

from app import Matrix
from keyboard_core import KeyboardState, Profile, KeyCalibration


class MatrixLayoutTests(unittest.TestCase):
    def check_layout(self, width, height):
        root = tk.Tk()
        root.attributes("-alpha", 0)
        root.geometry(f"{width}x{height}")
        canvas = Matrix(root, lambda index: None)
        canvas.pack(fill="both", expand=True)
        root.update()
        self.assertEqual((canvas.winfo_width(), canvas.winfo_height()), (width, height))
        canvas.layout()
        now = time.monotonic()
        model = KeyboardState(Profile([KeyCalibration(900, 120)] * 32))
        for key in range(1, 33):
            model.update(key, 900, now)
        canvas.refresh(model, 0, now)
        root.update_idletasks()
        try:
            for cell in canvas.cells:
                rect, title, badge, value, raw, bar = cell
                boxes = [canvas.bbox(item) for item in (title, value, raw) if canvas.itemcget(item, "state") != "hidden"]
                for i, first in enumerate(boxes):
                    for second in boxes[i + 1:]:
                        overlap_x = min(first[2], second[2]) - max(first[0], second[0])
                        overlap_y = min(first[3], second[3]) - max(first[1], second[1])
                        self.assertFalse(overlap_x > 1 and overlap_y > 1, (width, height, first, second))
        finally:
            root.destroy()

    def test_small_matrix_has_no_overlapping_labels(self):
        self.check_layout(700, 230)

    def test_normal_matrix_has_no_overlapping_labels(self):
        self.check_layout(940, 365)


if __name__ == "__main__":
    unittest.main()
