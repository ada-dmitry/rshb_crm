require "test_helper"

class SiteIconsTest < ActionDispatch::IntegrationTest
  test "page links to SVG and PNG icons including the touch icon" do
    get root_path

    assert_response :success
    assert_select "link[rel='icon'][type='image/svg+xml'][href='/icon.svg']"
    assert_select "link[rel='icon'][type='image/png'][href='/icon.png']"
    assert_select "link[rel='apple-touch-icon'][href='/icon.png']"
  end

  test "icons include a scalable green sprout and a 512 pixel PNG fallback" do
    svg = Nokogiri::XML(File.read(Rails.root.join("public/icon.svg")))
    svg.remove_namespaces!
    assert_equal "0 0 64 64", svg.root["viewBox"]
    assert_equal "#1f5c40", svg.at_xpath("/svg/rect")&.[]("fill")
    assert_operator svg.xpath("/svg/path").length, :>=, 2

    png = File.binread(Rails.root.join("public/icon.png"))
    assert_equal "\x89PNG\r\n\x1a\n".b, png.byteslice(0, 8)
    assert_equal [ 512, 512 ], png.byteslice(16, 8).unpack("NN")
  end
end
