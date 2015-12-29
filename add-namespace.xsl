<?xml version="1.0"?>

<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0"
  xmlns:mets="http://www.loc.gov/METS/"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/METS/ http://www.loc.gov/standards/mets/version191/mets.xsd">

  <xsl:output indent="yes"/>
  <xsl:strip-space elements="*"/>

  <xsl:template match="@*|node()">
    <xsl:copy copy-namespaces="no">
    <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="mets:mets">
    <xsl:element name="mets:{local-name()}">
      <xsl:attribute name="xsi:schemaLocation">
        <xsl:value-of select="document('')/*/@xsi:schemaLocation"/>
      </xsl:attribute>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="mets:metsHdr">
    <xsl:processing-instruction name="AIPTemplate">version="info:nyu/dl/v1.0/templates/aip/v1.0.1"</xsl:processing-instruction>
    <xsl:element name="mets:{local-name()}">
    <xsl:apply-templates select="@*|node()"/>
  </xsl:element>
  </xsl:template>

  <xsl:template match="*">
    <xsl:element name="mets:{local-name()}">
      <xsl:apply-templates select="@*|node()"/>
    </xsl:element>
  </xsl:template>

</xsl:stylesheet>
