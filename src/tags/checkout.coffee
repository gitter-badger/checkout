View = require '../view'
analytics = require '../utils/analytics'
checkoutHTML = require '../../templates/checkout'

require 'crowdstart.js/src/index'
require '../../vendor/js/select2'

form = require '../utils/form'
currency = require '../utils/currency'
Card = require 'card'
Order = require '../models/order'

events = require '../events'

progressBar = require './progressbar'

checkoutCSS = require '../../css/checkout'
loaderCSS = require '../../css/loader'
select2CSS = require '../../vendor/css/select2'

$ ->
  $('head')
    .append($("<style>#{ select2CSS }</style>"))
    .append($("<style>#{ checkoutCSS }</style>"))
    .append($("<style>#{ loaderCSS }</style>"))

class CheckoutView extends View
  tag: 'checkout'
  html: checkoutHTML
  checkingOut: false
  clickedApplyPromoCode: false
  checkingPromoCode: false
  constructor: ()->
    super(@tag, @html, @js)
  js: (opts, view)->
    self = @

    screenIndex = view.screenIndex = 0
    screens = view.screens = opts.config.screens
    screenCount = screens.length

    items = (screen.name for screen in screens)
    items.push 'Done!'

    view.api = opts.api

    progressBar.setItems items

    @callToActions = opts.config.callToActions

    @showSocial = opts.config.facebook != '' || opts.config.googlePlus != '' || opts.config.twitter != ''
    @user = opts.model.user
    @payment = opts.model.payment
    @order = opts.model.order
    @order.taxRate = 0

    @coupon = {}
    @showPromoCode = opts.config.showPromoCode == true

    @currency = currency
    @removeError = form.removeError

    $ ->
      requestAnimationFrame ->
        window.location.hash = ''
        screenCountPlus1 = screenCount + 1
        $('.crowdstart-screen-strip').css(width: '' + (screenCountPlus1 * 105) + '%')
          .find('form')
          .parent()
          .css(
            width: '' + ((100/105 * 100) / screenCountPlus1) + '%'
            'margin-right': '' + ((5/105 * 100) / screenCountPlus1) + '%')
          .last()
          .css
            'margin-right': 0

        $('.crowdstart-checkout .crowdstart-quantity-select')
          .select2(minimumResultsForSearch: Infinity)
          .on 'change', ()->
            $el = $(@)
            i = parseInt $el.attr('data-index'), 10
            items = self.order.items
            if items? && items[i]?
              item = items[i]
              quantity= item.quantity
              item.quantity = parseInt $el.val(), 10

              deltaQuantity = item.quantity - quantity
              if deltaQuantity > 0
                analytics.track 'Added Product',
                  id: item.productId
                  sku: item.productSlug
                  name: item.productName
                  quantity: deltaQuantity
                  price: parseFloat(item.price / 100)
              else if deltaQuantity < 0
                analytics.track 'Removed Product',
                  id: item.productId
                  sku: item.productSlug
                  name: item.productName
                  quantity: deltaQuantity
                  price: parseFloat(item.price / 100)

              if item.quantity == 0
                for j in [i..items.length-2] by 1
                  items[j] = items[j+1]
                items.length--
                $el.select2('val', items[i].quantity)
            self.update()

        view.reset()
        view.updateIndex(0)

    @invalidCode = false

    @updatePromoCode = (event) => @view.updatePromoCode(event)
    @submitPromoCode = (event) => @view.submitPromoCode(event)
    @escapeError = () =>
      @error = false
      requestAnimationFrame ()=>
        @view.updateIndex(0)
        @update()
    @close = (event) => @view.close(event)
    @next = (event) => @view.next(event)
    @back = (event) => @view.back(event)
    @toUpper = (event)->
      $el = $(event.target)
      $el.val($el.val().toUpperCase())

    @togglePromoCode = ()=> @showPromoCode = !@showPromoCode

  updateIndex: (i)->
    @screenIndex = i
    screenCount = @screens.length
    screenCountPlus1 = screenCount + 1

    progressBar.setIndex i

    $forms = $('.crowdstart-screens form')
    $forms
      .find('input, select, .select2-selection, a')
      .attr('tabindex', '-1')

    if $forms[i]?
      $form = $($forms[i])
      $form.find('input, select, a').removeAttr('tabindex')
      $form.find('.select2-selection').attr('tabindex', '0')

    $('.crowdstart-screen-strip')
      .css
        '-ms-transform': 'translateX(-' + (100 / screenCountPlus1 * i) + '%)'
        '-webkit-transform': 'translateX(-' + (100 / screenCountPlus1 * i) + '%)'
        transform: 'translateX(-' + (100 / screenCountPlus1 * i) + '%)'

  reset: ->
    @checkingOut = false
    @finished = false
    if @ctx.error == true
      @updateIndex(0)
      @ctx.error = false

  subtotal: ->
    items = @ctx.order.items
    subtotal = 0
    for item in items
      subtotal += item.price * item.quantity
    subtotal -= @discount()

    @ctx.order.subtotal = subtotal
    return subtotal

  shipping: ->
    items = @ctx.order.items
    shippingRate = @ctx.order.shippingRate || 0
    # shipping = 0
    # for item in items
    #   shipping += shippingRate * item.quantity

    # return @ctx.order.shipping = shipping
    return @ctx.order.shipping = shippingRate

  updatePromoCode: (event)->
    if event.target.value.length > 0
      @ctx.coupon.code = event.target.value
      @clickedApplyPromoCode = false
      setTimeout ()=>
        if !@clickedApplyPromoCode
          form.showError $('#crowdstart-promocode'), 'Don\'t forget to apply your coupon'
      , 1000

  submitPromoCode: ->
    if @ctx.coupon.code?
      @clickedApplyPromoCode = true
      form.removeError target: $('#crowdstart-promocode')[0]
      if @checkingPromoCode
        return
      @checkingPromoCode = true
      @ctx.opts.api.getCouponCode @ctx.coupon.code, (coupon)=>
        if coupon.enabled
          @ctx.coupon = coupon
          @ctx.order.couponCodes = [coupon.code]
        else
          @ctx.invalidCode = 'expired'
        @checkingPromoCode = false
        @update()
      , =>
        @ctx.invalidCode = 'invalid'
        @checkingPromoCode = false
        @update()

  discount: ->

    switch @ctx.coupon.type
      when 'flat'
        if !@ctx.coupon.productId? || @ctx.coupon.productId == ''
          return (@ctx.coupon.amount || 0)
        else
          discount = 0
          for item in @ctx.order.items
            if item.productId == @ctx.coupon.productId
              discount += (@ctx.coupon.amount || 0) * item.quantity
          return discount

      when 'percent'
        discount = 0
        if !@ctx.coupon.productId? || @ctx.coupon.productId == ''
          for item in @ctx.order.items
            discount += (@ctx.coupon.amount || 0) * item.price * item.quantity * 0.01
        else
          for item in @ctx.order.items
            if item.productId == @ctx.coupon.productId
              discount += (@ctx.coupon.amount || 0) * item.quantity * 0.01
        return Math.floor discount

    return 0

  tax: ->
    return @ctx.order.tax = Math.ceil((@ctx.order.taxRate || 0) * @subtotal())

  total: ->
    total = @subtotal() + @shipping() + @tax()

    @ctx.order.total = total
    return total

  close: ->
    if @finished
      setTimeout ()=>
        @ctx.order = new Order()
      , 500
    setTimeout ()=>
      @update()
      @reset()
    , 500
    $('modal').removeClass('crowdstart-active')

  back: ->
    if @locked
      return

    if @screenIndex <= 0
      @close()
    else
      @updateIndex @screenIndex - 1

  next: ->
    if @locked
      return

    @locked = true
    if !@checkingOut
      terms = $ '.crowdstart-terms #terms'
      if !terms.prop('checked')
        form.showError terms, 'You should read and agree to these terms.'
        removeTermError = (event)->
          if terms.prop('checked')
            form.removeError event
            terms.off 'change', removeTermError
        terms.on 'change', removeTermError
        @locked = false
        @update()
        return

      @screens[@screenIndex].validate =>
        if @screenIndex >= @screens.length - 1

          analytics.track 'Completed Checkout Step',
            step: @screenIndex + 1

          @checkingOut = true
          @ctx.opts.api.charge @ctx.opts.model, (order)=>

            @updateIndex @screenIndex + 1

            analytics.track 'Viewed Checkout Step',
              step: @screenIndex + 1

            @locked = false
            @finished = true

            options =
              orderId:  order.id
              total:    parseFloat(order.total/100),
              # revenue: parseFloat(order.total/100),
              shipping: parseFloat(order.shipping/100),
              tax:      parseFloat(order.tax/100),
              discount: parseFloat(order.discount/100),
              coupon:   @ctx.coupon.code || '',
              currency: order.currency,
              products: []

            for item, i in order.items
              options.products[i] =
                id: item.productId
                sku: item.productSlug
                name: item.productName
                quantity: item.quantity
                price: parseFloat(item.price / 100)

            analytics.track 'Completed Order', options

            window.Crowdstart.Events.trigger('checkout', order)

            if @ctx.opts.config.referralProgram?
              @ctx.opts.api.referrer order, @ctx.opts.config.referralProgram, (referrer) =>
                @ctx.referrerId = referrer.id
                @update()
              , ()=>
                @update()
            else
              @update()
            events.track @ctx.opts.config.pixels?.checkout
          , (xhr) =>
            @checkingOut = false
            @locked = false
            if xhr.status == 402 && xhr.responseJSON.error.code == 'card-declined'
              @ctx.error = "declined"
            else
              @ctx.error = "failed"
            @update()
        else
          @updateIndex @screenIndex + 1
          @locked = false
        @update()
      , =>
        @locked = false
        @update()

module.exports = new CheckoutView
