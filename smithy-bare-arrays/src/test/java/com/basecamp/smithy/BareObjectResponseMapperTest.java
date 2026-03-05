/*
 * Copyright Basecamp, LLC
 * SPDX-License-Identifier: Apache-2.0
 */
package com.basecamp.smithy;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.smithy.model.node.ObjectNode;

import static org.junit.jupiter.api.Assertions.*;

class BareObjectResponseMapperTest {

    private BareObjectResponseMapper mapper;

    @BeforeEach
    void setUp() {
        mapper = new BareObjectResponseMapper();
    }

    @Test
    void shouldTransform_matchesGetResponseContentWithRef() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("project", ObjectNode.builder()
                                .withMember("$ref", "#/components/schemas/Project")
                                .build())
                        .build())
                .build();

        assertTrue(mapper.shouldTransform("GetProjectResponseContent", schema));
    }

    @Test
    void shouldTransform_rejectsInlineObjectWithoutRef() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("thing", ObjectNode.builder()
                                .withMember("type", "object")
                                .build())
                        .build())
                .build();

        assertFalse(mapper.shouldTransform("GetThingResponseContent", schema));
    }

    @Test
    void shouldTransform_matchesAnyPrefixWithResponseContentSuffix() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("project", ObjectNode.builder()
                                .withMember("$ref", "#/components/schemas/Project")
                                .build())
                        .build())
                .build();

        assertTrue(mapper.shouldTransform("CreateProjectResponseContent", schema));
        assertTrue(mapper.shouldTransform("UpdateProjectResponseContent", schema));
    }

    @Test
    void shouldTransform_rejectsNonResponseContentSuffix() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("project", ObjectNode.builder()
                                .withMember("$ref", "#/components/schemas/Project")
                                .build())
                        .build())
                .build();

        assertFalse(mapper.shouldTransform("GetProjectOutput", schema));
    }

    @Test
    void shouldTransform_rejectsMultipleProperties() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("person", ObjectNode.builder()
                                .withMember("$ref", "#/components/schemas/Person")
                                .build())
                        .withMember("todos", ObjectNode.builder()
                                .withMember("type", "array")
                                .build())
                        .withMember("grouped_by", ObjectNode.builder()
                                .withMember("type", "string")
                                .build())
                        .build())
                .build();

        assertFalse(mapper.shouldTransform("GetAssignedTodosResponseContent", schema));
    }

    @Test
    void shouldTransform_rejectsArrayProperty() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("events", ObjectNode.builder()
                                .withMember("type", "array")
                                .withMember("items", ObjectNode.builder()
                                        .withMember("$ref", "#/components/schemas/Event")
                                        .build())
                                .build())
                        .build())
                .build();

        assertFalse(mapper.shouldTransform("GetProjectTimelineResponseContent", schema));
    }

    @Test
    void shouldTransform_rejectsNonObjectType() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "array")
                .build();

        assertFalse(mapper.shouldTransform("GetProjectResponseContent", schema));
    }

    @Test
    void shouldTransform_rejectsNoProperties() {
        ObjectNode schema = ObjectNode.builder()
                .withMember("type", "object")
                .build();

        assertFalse(mapper.shouldTransform("GetProjectResponseContent", schema));
    }

    @Test
    void transformToRef_extractsRefSchema() {
        ObjectNode wrapped = ObjectNode.builder()
                .withMember("type", "object")
                .withMember("properties", ObjectNode.builder()
                        .withMember("project", ObjectNode.builder()
                                .withMember("$ref", "#/components/schemas/Project")
                                .build())
                        .build())
                .build();

        ObjectNode result = mapper.transformToRef(wrapped);

        assertEquals(
                "#/components/schemas/Project",
                result.expectStringMember("$ref").getValue()
        );
        // Should only have the $ref, no type or other keys
        assertFalse(result.getMember("type").isPresent());
    }

    @Test
    void getOrder_returnsHighValue() {
        assertTrue(mapper.getOrder() > 0);
    }
}
