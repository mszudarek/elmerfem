
INCLUDE_DIRECTORIES("${CMAKE_BINARY_DIR}/fem/src")
INCLUDE_DIRECTORIES("${CMAKE_SOURCE_DIR}/hutiter/include")

FILE(GLOB SRC_FILES *.src)

FOREACH(FNAME ${SRC_FILES})
  GET_FILENAME_COMPONENT(BASENAME ${FNAME} NAME_WE)
  ADD_CUSTOM_COMMAND(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${BASENAME}.F90
    COMMAND ${CMAKE_COMMAND} -E copy ${FNAME}
      ${CMAKE_CURRENT_BINARY_DIR}/${BASENAME}.F90
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${BASENAME}.src
  )
  ADD_LIBRARY(${BASENAME} MODULE ${BASENAME}.F90)
  SET_TARGET_PROPERTIES(${BASENAME} PROPERTIES PREFIX "")
  ADD_DEPENDENCIES(${BASENAME} elmersolver)
  INSTALL(TARGETS ${BASENAME} LIBRARY DESTINATION "share/elmersolver/lib")
ENDFOREACH()

