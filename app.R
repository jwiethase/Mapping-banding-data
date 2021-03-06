rm(list = ls(all=TRUE))  
library(shiny)
library(leaflet)
library(leaflet.extras)
library(dplyr)
library(scales)
library (lubridate)
library(raster)
library(sp)
library(rgdal)
library(data.table)
library(shinyjs)
library(shinyBS)
library(DT)
window_height <- htmlwidgets::JS('window.innerHeight')
window_width <- JS('window.innerWidth')
# Make the user interface
ui <- shiny::bootstrapPage(tags$style(" #loadmessage {
                                      position: fixed;
                                      top: 0px;
                                      left: 0px;
                                      width: 100%;
                                      padding: 5px 0px 5px 0px;
                                      text-align: center;
                                      font-weight: bold;
                                      font-size: 100%;
                                      color: #000000;
                                      background-color: #ffffff;
                                      z-index: 105;}",
                                      ".test_type {font-size: 12px}",
                                      type = "text/css", "html, body {width:100%;height:100%}",
                                      ".selectize-input { font-size: 12px; line-height: 12px;} .selectize-dropdown { font-size: 12px; line-height: 12px; }",
                                      HTML(".shiny-notification {
                                           position: fixed;
                                           top: calc(40%);;
                                           left: calc(30%);;
                                           }")),
                           conditionalPanel(condition="$('html').hasClass('shiny-busy')",
                                            tags$div("Loading...",id="loadmessage")),
                           # Make map span the whole area
                           leaflet::leafletOutput("map", width = "100%", height = "100%"),
                           
                           shinyjs::useShinyjs(), # Use for toggling slide input
                           
                           # Add a side panel for inputs
                           shiny::absolutePanel(top = "1%", right = "1%", width = "280px", height = "500px",
                                                div(style = "display:inline-block;width:100%;text-align: right",
                                                    bsButton("showpanel", " ", type = "toggle", value = TRUE, icon = icon("angle-double-down", lib = "font-awesome"))),
                                                draggable = FALSE,
                                                shiny::wellPanel(id = "Sidebar",
                                                                 div(class="test_type",
                                                                     id = "tPanel",style = "overflow-y:hidden;overflow-x: hidden;
                                                                     max-height: 80%;opacity: 1;font-size:80%;",
                                                                     shiny::actionButton("helptext", "?", style='padding:4px; font-size:80%;
                                                                                         position: absolute;top: 60px;right: 70px;'),
                                                                     shiny::fileInput(inputId = 'dataset', 
                                                                                      label = h5('Choose .csv file to upload'),
                                                                                      accept = c('.csv')),
                                                                     # uiOutput("out"),
                                                                     uiOutput("HelpBox1"),
                                                                     uiOutput("HelpBox2"),
                                                                     uiOutput("HelpBox3"),
                                                                     uiOutput("HelpBox4"),
                                                                     uiOutput("HelpBox5"),
                                                                     uiOutput("HelpBox6"),
                                                                     uiOutput("Species"),
                                                                     uiOutput("checkbox"),
                                                                     conditionalPanel("output.fileUploaded == true",
                                                                                      a(id = "toggleAdvanced", "Show/hide advanced controls"),
                                                                                      shinyjs::hidden(
                                                                                        div(id = "advanced",
                                                                     splitLayout(
                                                                             shiny::checkboxInput("idw", "Interpolation (idw)", FALSE),
                                                                             shiny::checkboxInput("circles", "Circle markers", TRUE)
                                                                           ),
                                                                     splitLayout(
                                                                             shiny::checkboxInput("cluster", "Clustered markers", FALSE),
                                                                             shiny::checkboxInput("richness", "Show richness", FALSE)
                                                                           ),
                                                                     shiny::checkboxInput("labels", "Static labels", TRUE),
                                                                           hr(),
                                                                           uiOutput("sliderCircle"),
                                                                           uiOutput("slider"),
                                                                           downloadButton('downloadData', 'Download')
                                                                     )
                                                                     )
                                                                 )))
)
,
shinyjs::hidden(
  div(
    id = "cp1",
    conditionalPanel("input.map_shape_click",
                     absolutePanel(top = "5%", bottom = "10%", right = "20%", left = "5%", height = "40%", width = "64%", 
                                   div(style = "display:inline-block;width:100%;text-align: right;",
                                       actionButton("close", "x")),
                                   wellPanel(div(id = "tablepanel",
                                                 style =  "overflow-y: scroll;overflow-x: scroll; max-height: 500px; max-width: 1200px",
                                                 dataTableOutput("clickInfo")
                                   )
                                   ), draggable = TRUE
                     )
    )
  )
)

)

# Make the server functions
server <- function(input, output, session) {
  options(shiny.maxRequestSize=100*1024^2) 
  observeEvent(input$showpanel, {
    
    if(input$showpanel == TRUE) {
      removeCssClass("Main", "col-sm-12")
      addCssClass("Main", "col-sm-8")
      shinyjs::show(id = "Sidebar")
      shinyjs::enable(id = "Sidebar")
    }
    else {
      removeCssClass("Main", "col-sm-8")
      addCssClass("Main", "col-sm-12")
      shinyjs::hide(id = "Sidebar")
    }
  })
  
  shinyjs::onclick("toggleAdvanced",
                   shinyjs::toggle(id = "advanced", anim = TRUE))    
  
  observeEvent(input$map_shape_click,{
    shinyjs::show("cp1")
  })
  observeEvent(input$close,{
    shinyjs::hide("cp1")
  })
  
  data <- reactive({
    req(input$dataset)
    data <- fread(input$dataset$datapath) 
    if(is.null(input$dataset)) return(NULL)
    
    req.names <- c("Species", "Latitude", "Longitude")
    if(all(req.names %in% colnames(data), TRUE) == FALSE){
      showNotification(paste("\nError: Missing or miss-spelled columns: ", paste(c(req.names[req.names %in% colnames(data) == FALSE]), collapse="\n"), sep=""),
                       duration = 5, type = "error"
      )
      validate(
        need(all(req.names %in% colnames(data), TRUE) == TRUE,
             message = FALSE
        )
      )
    }
    
    if("Site" %in% names(data) == FALSE){
      data$Site <- data %>%
        group_by(Latitude, Longitude) %>% 
        group_indices()
    }
    
    if(length(data$Site) >= 50){
      updateCheckboxInput(session, "labels", value = FALSE)
    }
    
    if("Date" %in% names(data)){
      data <- data %>%
        mutate(Date = lubridate::dmy(Date),
               year = lubridate::year(Date))
    }
    # Check for non-numeric values in Latitude and Longitude column
    coordsDF <- data %>% dplyr::select(Latitude, Longitude) %>% mutate(Latitude = as.numeric(Latitude),
                                                                       Longitude = as.numeric(Longitude))
    if(identical(colnames(coordsDF)[colSums(is.na(coordsDF)) > 0], character(0)) == FALSE){
      showNotification( paste("\nWarning: Rows excluded due to non-numeric values in column: ", paste(c(colnames(coordsDF)[colSums(is.na(coordsDF)) > 0]), collapse="\n"), sep=""),
                        duration = 5, type = "warning"
      )
    }
    remove(coordsDF)
    
    data <- data %>%
      mutate(Latitude = as.numeric(as.character(Latitude)),
             Longitude = as.numeric(as.character(Longitude))) %>% 
      filter(!is.na(Latitude), !is.na(Longitude))
    
    return(data)
  })
  
  output$fileUploaded <- reactive({
    return(!is.null(data()))
  })
  outputOptions(output, 'fileUploaded', suspendWhenHidden=FALSE)
  
  
  observeEvent(data(), {
    output$Species <- renderUI({
      data <- data()
      Spec.choices <- data %>% dplyr::select(Species) %>% unique() %>% arrange(Species)
      Spec <- data.frame(Species = c("Select all", Spec.choices$Species))
      shiny::selectInput(inputId = "species.choices", 
                         label = h5("Species"),
                         choices = Spec$Species,
                         selected = Spec$Species[2],
                         multiple = TRUE)
    })
  })
  
  observe({
    data <- data()
    Spec.choices <- data %>% dplyr::select(Species) %>% unique() %>% arrange(Species)
    Spec <- data.frame(Species = c("Select all", Spec.choices$Species))
    if ("Select All" %in% input$species.choices) {
      # choose all the choices except "Select All"
      selected_choices <- setdiff(Spec$Species, "Select All")
      updateSelectInput(session, "species.choices", selected = selected_choices)
    }
  })
  
  observeEvent(data(), {
    output$Species <- renderUI({
      data <- data()
      Spec.choices <- data %>% dplyr::select(Species) %>% unique() %>% arrange(Species)
      shiny::selectInput(inputId = "species.choices", 
                         label = h5("Species"),
                         choices = Spec.choices$Species,
                         selected = Spec.choices$Species[1],
                         multiple = TRUE)
    })
  })
  
  Spec.choice <- reactive({
    gsub("[[:space:]]\\(.*$", "", input$species.choices)
  })
  
  # Modify the checkbox options for year depending on the subsetted dataframe
  observeEvent(
    {
    input$species.choices
    input$richness
    }, {
    if("Date" %in% names(data()) & input$richness == FALSE){
      output$checkbox <- renderUI({
        data <- data()
        choice <-  data.frame(year= unique(data[data$Species %in% Spec.choice(), "year"]))
        choice$year <- choice$year[order(choice$year, decreasing = TRUE)]
        checkboxGroupInput(inputId = "checkbox",
                           label = h5("Year"),
                           choices = choice$year, selected = choice$year)
      })
    }
      if("Date" %in% names(data()) & input$richness == TRUE){
        output$checkbox <- renderUI({
          data <- data()
          # choice <-  data.frame(year= unique(data$year))
          # choice$year <- choice$year[order(choice$year, decreasing = TRUE)]
          checkboxGroupInput(inputId = "checkbox",
                             label = h4("Year"),
                             choices = unique(data$year), selected =  unique(data$year))
        })
      }
  })
  output$HelpBox1 = renderUI({
    if (input$helptext %% 2){
      helpText("Warning: Dataset has to include all of the following column names:")
    } else {
      return()}
  })
  output$HelpBox2 = renderUI({
    if (input$helptext %% 2){
      helpText("'Species'")
    } else {
      return()}
  })
  output$HelpBox3 = renderUI({
    if (input$helptext %% 2){
      helpText("'Latitude' (Format: decimal)")
    } else {
      return()}
  })
  output$HelpBox4 = renderUI({
    if (input$helptext %% 2){
      helpText("'Longitude' (Format: decimal)")
    } else {
      return()}
  })
  output$HelpBox5 = renderUI({
    if (input$helptext %% 2){
      helpText("OPTIONAL 'Site'")
    } else {
      return()}
  })
  output$HelpBox6 = renderUI({
    if (input$helptext %% 2){
      helpText("OPTIONAL 'Date' (Format: dmy)")
    } else {
      return()}
  })
  
  
  # Filter the initial dataframe by species and year chosen
  filteredData <- shiny::reactive({
    data <- data()
    if("Date" %in% names(data)){
      data <- data[data$year %in% input$checkbox, ]
    }
    if(input$richness == FALSE){
      data <- data %>% group_by(Species, Longitude, Latitude, Site) %>% 
        summarize(abundance= n()) %>% ungroup() %>% dplyr::filter(Species %in% Spec.choice())
    } 
    if(input$richness == TRUE) {
      data <- data %>% group_by(Longitude, Latitude, Site) %>% 
        summarize(richness= length(unique(Species))) %>% ungroup()
    }
    data
  })
  
  # Filter the initial dataframe, but retain all columns. The product will be used for the download button 
  DataDetailed <- shiny::reactive({
    data <- data()
    if("Date" %in% names(data)){
      data <- data[data$year %in% input$checkbox, ]  
    }
    data
  })
  
  # Make a leaflet map that won't change with the user's input
  output$map <- leaflet::renderLeaflet({
    leaflet::leaflet() %>%  
      addProviderTiles(providers$Esri.WorldImagery, group = "Esri.WorldImagery", options = providerTileOptions(minZoom = 2)) %>%
      addProviderTiles(providers$Esri.WorldTopoMap, group = "Esri.WorldTopoMap", options = providerTileOptions(minZoom = 2)) %>%
      addProviderTiles(providers$OpenMapSurfer.Roads, group = "OpenMapSurfer.Roads", options = providerTileOptions(minZoom = 2)) %>%
      addProviderTiles(providers$Esri.DeLorme, group = "Esri.DeLorme", options = providerTileOptions(minZoom = 2)) %>%
      addProviderTiles(providers$OpenTopoMap, group = "OpenTopoMap", options = providerTileOptions(minZoom = 2)) %>%
      addProviderTiles(providers$OpenStreetMap.Mapnik, group = "OpenStreetMap.Mapnik", options = providerTileOptions(minZoom = 2)) %>% 
      addProviderTiles(providers$Esri.WorldGrayCanvas, group = "Esri.WorldGrayCanvas", options = providerTileOptions(minZoom = 2)) %>% 
      addEasyButton(easyButton(
        icon = "fa-globe", title = "Zoom to Level 2",
        onClick = JS("function(btn, map){ map.setZoom(2);}"))) %>% 
      leaflet.extras::addSearchOSM() %>% 
      leaflet.extras::addFullscreenControl() %>%
      addLayersControl(
        baseGroups = c('Esri.WorldImagery', 'Esri.WorldTopoMap', 'OpenMapSurfer.Roads', 'Esri.DeLorme', 'OpenTopoMap', 'OpenStreetMap.Mapnik', 'Esri.WorldGrayCanvas'),
        options = layersControlOptions(collapsed = TRUE),
        position = "topleft"
      ) %>% 
      addMeasure(primaryLengthUnit="kilometers", secondaryLengthUnit="kilometers",
                 position = "topleft") %>% 
      addScaleBar(position = c("bottomleft"))
  })
  observeEvent(input$idw,{
    toggle("slider", condition = input$idw == TRUE)
  })
  observeEvent(input$circles,{
    toggle("sliderCircle", condition = input$circles == TRUE)
  })
  observeEvent(input$richness,{
    toggle("Species", condition = input$richness == FALSE)
  })
  
  # Update above leaflet map depending on user inputs
  
  shiny::observe({
    data <- data()
    sites <- data %>% dplyr::select(Longitude, Latitude, Site) %>% unique()
    
    map <- leaflet::leafletProxy(map = "map", data = filteredData())  %>% 
      leaflet::fitBounds(~min(Longitude+.5), ~min(Latitude-.5), ~max(Longitude+.5), ~max(Latitude+.5))
    
    if(input$circles == TRUE){
      
      map <- map  %>%  
        leaflet::fitBounds(~min(Longitude+.5), ~min(Latitude-.5), ~max(Longitude+.5), ~max(Latitude+.5))
      
      output$sliderCircle <- renderUI({
        sliderInput("circleSlider", "Circle size", min=10, max=2000, step = 10, value=1100)
      })
      outputOptions(output, "sliderCircle", suspendWhenHidden = FALSE)
      
      observeEvent(input$circleSlider, {
        if(input$richness == FALSE){
          map <- leaflet::leafletProxy(map = "map", data = filteredData())  %>% 
            clearImages() %>% 
            clearShapes() %>% 
            leaflet::addCircles(lng=~Longitude, lat=~Latitude, radius = ~scales::rescale(abundance, to=c(1,10))*((max(Longitude+0.3) - min(Longitude-0.3))*input$circleSlider), weight = 1, color = "darkred",
                                fillOpacity = 0.7, label = ~paste('Records: ', abundance, sep=''),
                                highlight = highlightOptions(
                                  weight = 3,
                                  color = "black",
                                  opacity = 1.0,
                                  bringToFront = TRUE,
                                  sendToBack = TRUE),
                                layerId = ~Site)
        } 
        if(input$richness == TRUE){
          map <- leaflet::leafletProxy(map = "map", data = filteredData())  %>% 
            clearImages() %>% 
            clearShapes() %>% 
            leaflet::addCircles(lng=~Longitude, lat=~Latitude, radius = ~scales::rescale(richness, to=c(1,10))*((max(Longitude+0.3) - min(Longitude-0.3))*input$circleSlider), weight = 1, color = "darkred",
                                fillOpacity = 0.7, label = ~paste('Records: ', richness, sep=''),
                                highlight = highlightOptions(
                                  weight = 3,
                                  color = "black",
                                  opacity = 1.0,
                                  bringToFront = TRUE,
                                  sendToBack = TRUE),
                                layerId = ~Site)
          
        }
        
      })
    } else {
      map <- map %>% 
        clearShapes()
    }
    
    if(input$idw == TRUE){ 
      new_df <- filteredData() %>% dplyr::rename(lon = "Longitude",
                                                 lat = "Latitude")
      if(length(rownames(new_df)) <= 1){
        showNotification("Not enough data for interpolation",
                         duration = 5, type = "error"
        )
      }
      validate(
        need(length(rownames(new_df)) > 1, message = FALSE)
      )
      map <- map  %>%  
        leaflet::fitBounds(~min(Longitude+.2), ~min(Latitude-.2), ~max(Longitude+.2), ~max(Latitude+.2))
      
      output$slider <- renderUI({
        sliderInput("Slider", "Inverse Distance Weighting Power", min=0, max=5, value=2)
      })
      outputOptions(output, "slider", suspendWhenHidden = FALSE)
      
      observeEvent(input$Slider, {
  
        coords <- cbind(new_df$lon, new_df$lat)
        sp = sp::SpatialPoints(coords)
        spdf = sp::SpatialPointsDataFrame(sp, new_df)
        sp::proj4string(spdf) <- CRS("+init=epsg:4326")
        
        # Create an empty grid where n is the total number of cells
        x.range <- as.numeric(c(min(new_df$lon - 1), max(new_df$lon +
                                                           1)))  # min/max longitude of the interpolation area
        y.range <- as.numeric(c(min(new_df$lat - 1), max(new_df$lat +
                                                           1)))  # min/max latitude of the interpolation area
        
        extent <- data.frame(lon = c(min(new_df$lon - 0.5), max(new_df$lon +
                                                                  0.5)), lat = c(min(new_df$lat - 0.5), max(new_df$lat +
                                                                                                              0.5)))
        # expand points to grid
        grd <- expand.grid(x = seq(from = x.range[1], to = x.range[2],
                                   by = round((log(length(rownames(new_df)))) * 0.004, digits = 3)),
                           y = seq(from = y.range[1],
                                   to = y.range[2],
                                   by = round((log(length(rownames(new_df)))) * 0.004, digits = 3)))
        
        sp::coordinates(grd) <- ~x + y
        sp::gridded(grd) <- TRUE
        
        # Add P's projection information to the empty grid
        sp::proj4string(grd) <- sp::proj4string(spdf)
        
        # Run the interpolation 
        if(input$richness == FALSE){
          P.idw <- gstat::idw(new_df$abundance ~ 1, locations = spdf, newdata = grd, idp = input$Slider)
        }
        
        if(input$richness == TRUE){
          P.idw <- gstat::idw(new_df$richness ~ 1, locations = spdf, newdata = grd, idp = input$Slider)
        }
        
        # Convert to raster object
        r <- raster::raster(P.idw)
        pal <- colorNumeric(c("#FFFFCC", "#41B6C4", "#0C2C84"), values(r),
                            na.color = "transparent")
        
        map <- map %>% 
          clearImages() %>% 
          clearShapes() %>% 
          leaflet::addRasterImage(r, colors = pal, opacity = 0.8) %>%
          clearControls() 
      })
    } else {
      map <- map %>% 
        clearImages()
    }
    
    observeEvent({
      input$labels
      input$cluster
    }, {
      map <- map %>% 
        clearMarkers() %>% 
        clearControls() %>% 
        clearMarkerClusters() 
      if(input$cluster == TRUE){
        map <- map %>% 
          leaflet::addMarkers(data= sites,lng=~Longitude, lat=~Latitude, label = ~as.character(Site),
                              clusterOptions = markerClusterOptions(),
                              labelOptions = labelOptions(noHide = input$labels),
                              layerId = ~Site) 
      } else {
        map <- map %>% 
          leaflet::addMarkers(data= sites,lng=~Longitude, lat=~Latitude, label = ~as.character(Site),
                              labelOptions = labelOptions(noHide = input$labels),
                              layerId = ~Site)
      }
    })
  })
  
  
  # output$out <- renderPrint({
  #   validate(need(input$map_click, FALSE))
  #   output$out <- renderUI({
  #     df <- input$map_click
  #     textInput("Coords", "Clicked coordinates:", value = paste(round(df[[1]], digits= 4), ", ", round(df[[2]], digits= 4), sep = ""))
  #   })
  # })
  # 
  # observeEvent(input$map_click, {
  #   click <- input$map_click
  #   leafletProxy('map') %>%
  #     removeMarker(layerId = click$id) %>% 
  #     leaflet::addCircleMarkers(data = click, lng=~lng, lat=~lat, layerId = ~id, radius = 2, opacity = 1,
  #                               stroke = FALSE, color = "black")
  # })
  observeEvent(input$map_shape_click, {
    data <- DataDetailed()
    click <- input$map_shape_click
    if(input$richness == FALSE) {
      data <- data %>% filter(Site == click$id,
                              Species %in% Spec.choice())
    }
    if(input$richness == TRUE) {
      data <- data %>% 
        filter(Site == click$id) %>% 
        group_by(Species, Site, Latitude, Longitude) %>% 
        summarize(abundance = n())
    }
    output$clickInfo <- DT::renderDataTable({data}, options = list(scrollX = FALSE, paging = FALSE))
  }) 
  
  # Download the filtered dataframe
  output$downloadData <- downloadHandler(
    filename = function() { 
      paste("data_", Sys.time(), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(DataDetailed(), file, row.names = FALSE)
    })
}

shiny::shinyApp(ui, server)
