<template>
    <div v-if="count > 0">
        {{ count }} / {{ max }}
    </div>
</template>

<script>
    export default {
        name: "VoteCount",
        props: ["count", "max"]
    }
</script>