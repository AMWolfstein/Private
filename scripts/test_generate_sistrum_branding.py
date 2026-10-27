"""Host branding regressions; run with Python + Pillow, no APK/device needed."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'
RES = ROOT / 'android/app/src/main/res'


class SistrumBrandingTest(unittest.TestCase):
    def test_full_colour_inputs_preserve_owner_source_exactly(self):
        original = (ROOT / 'logo/logo.png').read_bytes()
        for name in ['icon.png', 'icon_foreground_android.png',
                     'assets/images/logo.png', 'assets/images/logo-transparent.png']:
            with self.subTest(name=name):
                self.assertEqual(original, (ROOT / name).read_bytes())

    def test_monochrome_keeps_source_alpha_not_a_solid_square(self):
        source = Image.open(ROOT / 'logo/logo.png').convert('RGBA')
        mask = Image.open(ROOT / 'icon_monochrome_android.png').convert('RGBA')
        self.assertIsNone(ImageChops.difference(source.getchannel('A'), mask.getchannel('A')).getbbox())
        self.assertEqual((0, 255), mask.getchannel('A').getextrema())
        for channel in mask.split()[:3]:
            self.assertEqual((255, 255), channel.getextrema())

    def test_android12_splash_keeps_adaptive_safe_inset_in_both_modes(self):
        # Passing the full foreground directly to the splash theme clips the mark.
        for variant in ['values-v31', 'values-night-v31']:
            with self.subTest(variant=variant):
                style = ET.parse(RES / variant / 'styles.xml').getroot().find('style')
                items = {item.attrib['name']: item.text for item in style.findall('item')}
                self.assertEqual('@drawable/sistrum_splash_icon', items['android:windowSplashScreenAnimatedIcon'])
                self.assertEqual('@color/ic_launcher_background', items['android:windowSplashScreenBackground'])
        inset = ET.parse(RES / 'drawable-v31/sistrum_splash_icon.xml').getroot()
        self.assertEqual('16%', inset.attrib[ANDROID + 'inset'])
        self.assertEqual('@drawable/ic_launcher_foreground', inset.attrib[ANDROID + 'drawable'])
        launcher = ET.parse(RES / 'mipmap-anydpi-v26/ic_launcher.xml').getroot()
        self.assertEqual(inset.attrib[ANDROID + 'inset'], launcher.find('foreground/inset').attrib[ANDROID + 'inset'])


if __name__ == '__main__':
    unittest.main()
