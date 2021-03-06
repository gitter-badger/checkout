assert    = require 'assert'
should    = require('chai').should()

{getBrowser, TIMEOUT} = require './util'

parsePrice = (str) ->
  str = str.substring(1, str.length) # strip $
  parseFloat str


describe "Checkout (#{process.env.BROWSER})", ->
  testPage = "http://localhost:#{process.env.PORT ? 3333}/widget.html"

  openWidget = (browser) ->
    browser
      .url testPage

      .waitForExist 'modal', TIMEOUT

      # Click the Buy button
      .click 'a.btn'
      .waitForExist '.crowdstart-active', TIMEOUT
      .waitForExist '.crowdstart-line-item'
      .waitForVisible '.crowdstart-line-item:nth-child(2) .select2'

  describe 'Changing the quantity of a line item', ->
    it 'should update line item cost', (done) ->
      unitPrice = 0

      openWidget getBrowser()
        # Select 2 for 'Such T-shirt
        .selectByValue('.crowdstart-invoice > div:nth-child(2) select', '2')

        .getText 'div.crowdstart-invoice > div:nth-child(2) > div:nth-child(2) > div:nth-child(2) > span:nth-child(1)'
        .then (text) ->
          console.log text
          unitPrice = parsePrice text

        .getText 'div.crowdstart-invoice > div:nth-child(2) > div:nth-child(2) > div.crowdstart-col-1-3-bl.crowdstart-text-right.crowdstart-money'
        .then (text) ->
          console.log text
          lineItemPrice = parsePrice text
          assert.strictEqual lineItemPrice, unitPrice * 2
        .end done

  describe 'Completing the form', ->
    it 'should work', (done) ->
      openWidget getBrowser()
        # Payment information
        .setValue 'input#crowdstart-credit-card', '4242424242424242'
        .setValue 'input#crowdstart-expiry', '1122'
        .setValue '#crowdstart-cvc', '424'
        .click 'label[for=terms]'
        .click 'a.crowdstart-checkout-button'

        # Billing information
        .waitForVisible '#crowdstart-line1'
        .setValue '#crowdstart-line1', '1234 fake street'
        .setValue '#crowdstart-city', 'fake city'
        .setValue '#crowdstart-state', 'fake state'
        .setValue '#crowdstart-postalCode', '55555'
        .click 'a.crowdstart-checkout-button'

        .waitForExist '.crowdstart-loader', TIMEOUT, true
        .getText '.crowdstart-thankyou > form > h1'
        .then (text) ->
          assert.strictEqual text, 'Thank You'
        .end done
