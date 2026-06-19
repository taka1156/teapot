export async function onRequest(context) {
    const response = await context.env.ASSETS.fetch(context.request);

    return new Response(response.body, {
        status: 418,
        statusText: "I'm a teapot",
        headers: response.headers,
    });
}
